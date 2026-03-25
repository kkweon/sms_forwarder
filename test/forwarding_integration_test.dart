import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/sms_forwarder_page.dart';
import 'package:sms_forwarder/sms_utils.dart';

import 'fake_sms_service.dart';

/// Pumps [SmsForwarderPage] with a [FakeSmsService] and permissions pre-granted.
/// [SharedPreferences] must be mocked before calling this.
Future<FakeSmsService> _buildPage(WidgetTester tester) async {
  final fake = FakeSmsService();
  await tester.pumpWidget(MaterialApp(
    home: SmsForwarderPage(
      smsService: fake,
      permissionsGrantedOverride: true,
    ),
  ));
  // Wait for async init (_checkPermissions, _loadSettings).
  await tester.pumpAndSettle();
  return fake;
}

/// Adds a destination number via the UI and waits for the state update.
Future<void> _addDestination(WidgetTester tester, String number) async {
  await tester.enterText(find.byType(TextField), number);
  await tester.tap(find.byIcon(Icons.add_circle));
  await tester.pump();
}

/// Enables the forwarding switch (requires at least one destination to be set).
Future<void> _enableForwarding(WidgetTester tester) async {
  await tester.tap(find.byType(Switch));
  await tester.pump();
}

void main() {
  setUp(() {
    // Reset SharedPreferences to a clean state before each test.
    SharedPreferences.setMockInitialValues({});
  });

  group('SMS forwarding — end-to-end user journey', () {
    testWidgets('BofA OTP message is forwarded after setup', (tester) async {
      final fake = await _buildPage(tester);

      await _addDestination(tester, '+12025550123');
      await _enableForwarding(tester);

      // Simulate the BofA SMS Retriever API OTP message arriving.
      fake.inject(makeSmsMessage(
        address: 'BofA',
        body: "<#>BofA: DO NOT share this Sign In code. We will NEVER call "
            "you or text you for it. Code 781265. Reply HELP if you didn't "
            "request it. 3olHr09B9Po",
      ));
      await tester.pumpAndSettle();

      expect(fake.sent, hasLength(1));
      expect(fake.sent.first.to, '+12025550123');
      expect(fake.sent.first.message, contains('781265'));
      // Forwarded message must not expose the raw <#> prefix.
      expect(fake.sent.first.message, isNot(contains('<#>')));
    });

    testWidgets('standard OTP message without SMS Retriever prefix is forwarded',
        (tester) async {
      final fake = await _buildPage(tester);
      await _addDestination(tester, '+12025550123');
      await _enableForwarding(tester);

      fake.inject(makeSmsMessage(
        address: 'Google',
        body: 'Your Google verification code is 654321',
      ));
      await tester.pumpAndSettle();

      expect(fake.sent, hasLength(1));
      expect(fake.sent.first.message, contains('654321'));
    });

    testWidgets('non-OTP message is NOT forwarded', (tester) async {
      final fake = await _buildPage(tester);
      await _addDestination(tester, '+12025550123');
      await _enableForwarding(tester);

      fake.inject(makeSmsMessage(
        address: 'Mom',
        body: 'Hey are you coming for dinner tonight?',
      ));
      await tester.pumpAndSettle();

      expect(fake.sent, isEmpty);
    });

    testWidgets('message is NOT forwarded when forwarding is disabled',
        (tester) async {
      final fake = await _buildPage(tester);
      await _addDestination(tester, '+12025550123');
      // Intentionally do NOT enable forwarding.

      fake.inject(makeSmsMessage(
        address: 'BofA',
        body: 'Code 781265.',
      ));
      await tester.pumpAndSettle();

      expect(fake.sent, isEmpty);
    });

    testWidgets('message is forwarded to multiple destinations', (tester) async {
      final fake = await _buildPage(tester);
      await _addDestination(tester, '+12025550123');
      await _addDestination(tester, '+19998887777');
      await _enableForwarding(tester);

      fake.inject(makeSmsMessage(
        address: 'Chase',
        body: 'Your Chase verification code: 5544',
      ));
      await tester.pumpAndSettle();

      expect(fake.sent, hasLength(2));
      expect(fake.sent.map((s) => s.to),
          containsAll(['+12025550123', '+19998887777']));
    });
  });
}
