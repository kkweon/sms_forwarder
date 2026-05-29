import 'package:another_telephony/telephony.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/forwarding/platform_sms_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.kkweon.sms_forwarder/sms');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('PlatformSmsService', () {
    test(
      'invokes sendMultipartSms on our own channel with to/message',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'sent';
        });

        final service = PlatformSmsService();
        SendStatus? reported;
        await service.sendSms(
          to: '+12025550123',
          message: 'hello',
          isMultipart: true,
          statusListener: (s) => reported = s,
        );

        expect(calls, hasLength(1));
        expect(calls.single.method, 'sendMultipartSms');
        expect(calls.single.arguments, {
          'to': '+12025550123',
          'message': 'hello',
        });
        expect(reported, SendStatus.SENT);
      },
    );

    test('reports non-SENT status when platform returns "failed"', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => 'failed');

      final service = PlatformSmsService();
      SendStatus? reported;
      await service.sendSms(
        to: '+12025550123',
        message: 'hi',
        statusListener: (s) => reported = s,
      );

      expect(reported, isNot(SendStatus.SENT));
    });

    test('does not throw when the channel has no handler (regression: '
        'MissingPluginException(sendMultipartSms on '
        'plugins.shounakmulay.com/foreground_sms_channel) used to crash the '
        'NotificationDispatcher when MainActivity was not attached)', () async {
      // No mock handler registered for our channel — simulates the
      // listener-service-only path where MainActivity is gone.
      final service = PlatformSmsService();
      SendStatus? reported;
      await service.sendSms(
        to: '+12025550123',
        message: 'hi',
        statusListener: (s) => reported = s,
      );
      expect(reported, isNot(SendStatus.SENT));
    });

    test(
      'reports non-SENT status when platform throws PlatformException',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'SMS_FAIL', message: 'radio off');
        });

        final service = PlatformSmsService();
        SendStatus? reported;
        await service.sendSms(
          to: '+12025550123',
          message: 'hi',
          statusListener: (s) => reported = s,
        );
        expect(reported, isNot(SendStatus.SENT));
      },
    );
  });
}
