import 'dart:async';

import 'package:another_telephony/telephony.dart' show SendStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/forwarding/forward_reservation.dart';
import 'package:sms_forwarder/notifications/incoming_message.dart';
import 'package:sms_forwarder/notifications/notification_dispatcher.dart';

import 'fake_sms_service.dart';

void main() {
  late StreamController<IncomingMessage> ctrl;
  late FakeSmsService fakeSms;
  late NotificationDispatcher dispatcher;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Reset the process-wide reservation map between tests.
    ForwardReservation.reset();
    ctrl = StreamController<IncomingMessage>.broadcast();
    fakeSms = FakeSmsService();
    dispatcher = NotificationDispatcher(
      streamFactory: () => ctrl.stream,
      smsServiceFactory: () => fakeSms,
    );
    await dispatcher.start();
  });

  tearDown(() async {
    await dispatcher.stop();
    await ctrl.close();
  });

  Future<void> pumpEvent(IncomingMessage msg) async {
    ctrl.add(msg);
    // Let the async handler chain (settings load → planner → handler) complete.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  IncomingMessage code(String body, {String address = 'BofA'}) =>
      IncomingMessage(address: address, body: body);

  test('forwards a valid verification code to all destinations', () async {
    SharedPreferences.setMockInitialValues({
      'forwarding_enabled': true,
      'destination_numbers': ['+12025550123', '+19998887777'],
    });

    await pumpEvent(code('Your verification code is 123456'));

    expect(fakeSms.sent.length, 2);
    expect(fakeSms.sent.map((s) => s.to).toSet(), {
      '+12025550123',
      '+19998887777',
    });
    expect(fakeSms.sent.first.message, contains('123456'));
  });

  test('does nothing when forwarding is disabled', () async {
    SharedPreferences.setMockInitialValues({
      'forwarding_enabled': false,
      'destination_numbers': ['+12025550123'],
    });

    await pumpEvent(code('Your verification code is 123456'));

    expect(fakeSms.sent, isEmpty);
  });

  test('does nothing when no destination numbers configured', () async {
    SharedPreferences.setMockInitialValues({
      'forwarding_enabled': true,
      'destination_numbers': <String>[],
    });

    await pumpEvent(code('Your verification code is 123456'));

    expect(fakeSms.sent, isEmpty);
  });

  test('does nothing when message has no keyword match', () async {
    SharedPreferences.setMockInitialValues({
      'forwarding_enabled': true,
      'destination_numbers': ['+12025550123'],
    });

    await pumpEvent(code('See you at the office at 7pm'));

    expect(fakeSms.sent, isEmpty);
  });

  test('diagnostic event is logged and never reaches the SmsService', () async {
    SharedPreferences.setMockInitialValues({
      'forwarding_enabled': true,
      'destination_numbers': ['+12025550123'],
    });

    await pumpEvent(
      const IncomingMessage(
        packageName: 'com.example.other',
        diag: 'package_not_allowed',
      ),
    );

    expect(fakeSms.sent, isEmpty);
  });

  test('loop detection disables forwarding', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'forwarding_enabled': true,
      'destination_numbers': ['+12025550123'],
      'recent_forwards': List.filled(5, now.toString()),
    });

    await pumpEvent(code('Your verification code is 123456'));

    expect(fakeSms.sent, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getBool('forwarding_enabled'), isFalse);
    expect(prefs.getBool('loop_detected'), isTrue);
  });

  group('forward dedup (hybrid double-source)', () {
    test('same code fired twice in quick succession forwards once per '
        'destination (synchronous reservation)', () async {
      SharedPreferences.setMockInitialValues({
        'forwarding_enabled': true,
        'destination_numbers': ['+12025550123', '+19998887777'],
      });

      // Two sources (SmsReceiver + Messages notification) deliver the SAME
      // code nearly simultaneously, before either persists its dedup record.
      ctrl.add(code('Your verification code is 123456'));
      ctrl.add(code('Your verification code is 123456'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeSms.sent.length, 2); // not 4
      expect(fakeSms.sent.map((s) => s.to).toSet(), {
        '+12025550123',
        '+19998887777',
      });
    });

    test('a repeated identical code is deduped on a later event', () async {
      SharedPreferences.setMockInitialValues({
        'forwarding_enabled': true,
        'destination_numbers': ['+12025550123'],
      });

      await pumpEvent(code('Your verification code is 123456'));
      expect(fakeSms.sent.length, 1);

      fakeSms = FakeSmsService();
      await pumpEvent(code('Your verification code is 123456'));
      expect(fakeSms.sent, isEmpty); // blocked by cache + reservation
    });

    test('a failed send is not deduped, so a later attempt retries', () async {
      SharedPreferences.setMockInitialValues({
        'forwarding_enabled': true,
        'destination_numbers': ['+12025550123'],
      });

      // First attempt fails (DELIVERED maps to 'failed' in forwardSms).
      fakeSms = FakeSmsService(statusToReport: SendStatus.DELIVERED);
      await pumpEvent(code('Your verification code is 123456'));
      expect(fakeSms.sent.length, 1);

      // A later attempt for the same code must NOT be blocked.
      fakeSms = FakeSmsService();
      await pumpEvent(code('Your verification code is 123456'));
      expect(fakeSms.sent.length, 1);
    });
  });
}
