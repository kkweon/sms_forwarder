import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/incoming_message.dart';
import 'package:sms_forwarder/notification_dispatcher.dart';

import 'fake_sms_service.dart';

void main() {
  late StreamController<IncomingMessage> ctrl;
  late FakeSmsService fakeSms;
  late NotificationDispatcher dispatcher;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ctrl = StreamController<IncomingMessage>.broadcast();
    fakeSms = FakeSmsService();
    dispatcher = NotificationDispatcher.forTesting(
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
}
