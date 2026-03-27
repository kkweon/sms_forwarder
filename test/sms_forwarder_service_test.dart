import 'package:another_telephony/telephony.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/sms_forwarder_service.dart';
import 'package:sms_forwarder/sms_utils.dart';

import 'fake_sms_service.dart';

void main() {
  group('forwardSms', () {
    test('sends to a single destination and returns one LogEntry', () async {
      final fake = FakeSmsService();
      final entries = await forwardSms(
        smsService: fake,
        message: makeSmsMessage(address: 'BofA', body: 'Code 1234.'),
        destinationNumbers: ['+12025550123'],
      );

      expect(fake.sent.length, 1);
      expect(fake.sent[0].to, '+12025550123');
      expect(entries.length, 1);
      expect(entries[0].to, '+12025550123');
      expect(entries[0].status, 'sent');
    });

    test(
      'sends to multiple destinations and returns one LogEntry per recipient',
      () async {
        final fake = FakeSmsService();
        final entries = await forwardSms(
          smsService: fake,
          message: makeSmsMessage(address: 'BofA', body: 'Code 1234.'),
          destinationNumbers: ['+12025550123', '+19998887777', '+13335554444'],
        );

        expect(fake.sent.length, 3);
        expect(entries.length, 3);
        final tos = entries.map((e) => e.to).toSet();
        expect(
          tos,
          containsAll(['+12025550123', '+19998887777', '+13335554444']),
        );
      },
    );

    test('prepends "Fwd from <sender>:" to the message body', () async {
      final fake = FakeSmsService();
      await forwardSms(
        smsService: fake,
        message: makeSmsMessage(address: 'BofA', body: 'Code 1234.'),
        destinationNumbers: ['+12025550123'],
      );

      expect(fake.sent[0].message, startsWith('Fwd from BofA:\n'));
    });

    test(
      'preprocesses body — strips <#> prefix and 11-char hash suffix',
      () async {
        final fake = FakeSmsService();
        final entries = await forwardSms(
          smsService: fake,
          message: makeSmsMessage(
            address: 'BofA',
            body: '<#>Code 1234. 3olHr09B9Po',
          ),
          destinationNumbers: ['+12025550123'],
        );

        expect(fake.sent[0].message, isNot(contains('<#>')));
        expect(fake.sent[0].message, isNot(contains('3olHr09B9Po')));
        expect(entries[0].body, 'Code 1234.');
      },
    );

    test('uses "unknown" when address is null', () async {
      final fake = FakeSmsService();
      final entries = await forwardSms(
        smsService: fake,
        message: makeSmsMessage(address: null, body: 'Code 1234.'),
        destinationNumbers: ['+12025550123'],
      );

      expect(fake.sent[0].message, startsWith('Fwd from unknown:\n'));
      expect(entries[0].from, 'unknown');
    });

    test('returns empty list when destinationNumbers is empty', () async {
      final fake = FakeSmsService();
      final entries = await forwardSms(
        smsService: fake,
        message: makeSmsMessage(address: 'BofA', body: 'Code 1234.'),
        destinationNumbers: [],
      );

      expect(fake.sent, isEmpty);
      expect(entries, isEmpty);
    });

    test('returns failed status when SmsService reports FAILED', () async {
      // DELIVERED is the only non-SENT status; the service maps it to 'failed'.
      final fake = FakeSmsService(statusToReport: SendStatus.DELIVERED);
      final entries = await forwardSms(
        smsService: fake,
        message: makeSmsMessage(address: 'BofA', body: 'Code 1234.'),
        destinationNumbers: ['+12025550123'],
      );

      expect(entries[0].status, 'failed');
      expect(entries[0].failed, isTrue);
    });
  });
}
