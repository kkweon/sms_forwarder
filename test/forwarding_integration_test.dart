import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/log_entry.dart';
import 'package:sms_forwarder/sms_forwarder_page.dart';

/// Pumps [SmsForwarderPage] with permissions pre-granted.
/// [SharedPreferences] must be mocked before calling this.
Future<void> _buildPage(WidgetTester tester) async {
  // Make the viewport tall enough to render all cards without scrolling.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    const MaterialApp(home: SmsForwarderPage(permissionsGrantedOverride: true)),
  );
  await tester.pumpAndSettle();
}

Future<void> _addDestination(WidgetTester tester, String number) async {
  await tester.enterText(find.byType(TextField), number);
  await tester.tap(find.byIcon(Icons.add_circle));
  await tester.pump();
}

Future<void> _enableForwarding(WidgetTester tester) async {
  await tester.tap(find.byType(Switch));
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SMS Forwarder page — settings UI', () {
    testWidgets('forwarding toggle is disabled until a destination is added', (
      tester,
    ) async {
      await _buildPage(tester);

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets(
      'forwarding toggle becomes enabled after adding a destination',
      (tester) async {
        await _buildPage(tester);
        await _addDestination(tester, '+12025550123');

        final switchWidget = tester.widget<Switch>(find.byType(Switch));
        expect(switchWidget.onChanged, isNotNull);
      },
    );

    testWidgets('added destination number appears in the list', (tester) async {
      await _buildPage(tester);
      await _addDestination(tester, '+12025550123');

      expect(find.text('+12025550123'), findsOneWidget);
    });

    testWidgets('enabling forwarding persists to SharedPreferences', (
      tester,
    ) async {
      await _buildPage(tester);
      await _addDestination(tester, '+12025550123');
      await _enableForwarding(tester);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('forwarding_enabled'), isTrue);
    });

    testWidgets('disabling forwarding persists to SharedPreferences', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'forwarding_enabled': true,
        'destination_numbers': ['+12025550123'],
      });
      await _buildPage(tester);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('forwarding_enabled'), isFalse);
    });

    testWidgets('removing a destination number removes it from the list', (
      tester,
    ) async {
      await _buildPage(tester);
      await _addDestination(tester, '+12025550123');
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('+12025550123'), findsNothing);
    });
  });

  group('SMS Forwarder page — log display', () {
    testWidgets('shows "No messages forwarded yet" when log is empty', (
      tester,
    ) async {
      await _buildPage(tester);

      expect(find.text('No messages forwarded yet'), findsOneWidget);
    });

    testWidgets('displays log entries written by the background engine', (
      tester,
    ) async {
      final entry = LogEntry(
        time: '2026-01-01T12:00:00.000',
        from: 'BofA',
        to: '+12025550123',
        body: 'Code 781265',
        status: 'sent',
      );
      SharedPreferences.setMockInitialValues({
        'forwarding_log': [jsonEncode(entry.toJson())],
      });

      await _buildPage(tester);

      expect(find.textContaining('BofA'), findsOneWidget);
      expect(find.textContaining('+12025550123'), findsOneWidget);
      expect(find.textContaining('Code 781265'), findsOneWidget);
    });

    testWidgets('refresh button reloads logs from SharedPreferences', (
      tester,
    ) async {
      await _buildPage(tester);
      expect(find.text('No messages forwarded yet'), findsOneWidget);

      // Simulate background engine writing a new log entry.
      final entry = LogEntry(
        time: '2026-01-01T12:00:00.000',
        from: 'Chase',
        to: '+12025550123',
        body: 'Code 9876',
        status: 'sent',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('forwarding_log', [jsonEncode(entry.toJson())]);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.textContaining('Code 9876'), findsOneWidget);
    });

    testWidgets('clear button removes all log entries', (tester) async {
      final entry = LogEntry(
        time: '2026-01-01T12:00:00.000',
        from: 'Google',
        to: '+12025550123',
        body: 'Code 654321',
        status: 'sent',
      );
      SharedPreferences.setMockInitialValues({
        'forwarding_log': [jsonEncode(entry.toJson())],
      });

      await _buildPage(tester);
      expect(find.textContaining('Code 654321'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(find.text('No messages forwarded yet'), findsOneWidget);
    });
  });
}
