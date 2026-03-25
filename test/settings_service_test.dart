import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/log_entry.dart';
import 'package:sms_forwarder/settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsService forwardingEnabled', () {
    test('returns false by default', () async {
      final settings = await SettingsService.load();
      expect(settings.forwardingEnabled, isFalse);
    });

    test('returns true after setForwardingEnabled(true)', () async {
      final settings = await SettingsService.load();
      await settings.setForwardingEnabled(true);
      expect(settings.forwardingEnabled, isTrue);
    });

    test('persists across reload', () async {
      final settings = await SettingsService.load();
      await settings.setForwardingEnabled(true);

      final reloaded = await SettingsService.load();
      expect(reloaded.forwardingEnabled, isTrue);
    });
  });

  group('SettingsService destinationNumbers', () {
    test('returns empty list by default', () async {
      final settings = await SettingsService.load();
      expect(settings.destinationNumbers, isEmpty);
    });

    test('returns saved numbers after setDestinationNumbers()', () async {
      final settings = await SettingsService.load();
      await settings.setDestinationNumbers(['+12025550123', '+19998887777']);
      expect(settings.destinationNumbers, ['+12025550123', '+19998887777']);
    });

    test('persists across reload', () async {
      final settings = await SettingsService.load();
      await settings.setDestinationNumbers(['+12025550123']);

      final reloaded = await SettingsService.load();
      expect(reloaded.destinationNumbers, ['+12025550123']);
    });
  });

  group('SettingsService forwardingLogs', () {
    test('returns empty list by default', () async {
      final settings = await SettingsService.load();
      expect(settings.forwardingLogs, isEmpty);
    });

    test('returns deserialized entries after saveLogs()', () async {
      final settings = await SettingsService.load();
      final logs = [
        const LogEntry(
          time: '2024-01-01T00:00:00.000',
          from: 'BofA',
          to: '+12025550123',
          body: 'Code 1234.',
          status: 'sent',
        ),
        const LogEntry(
          time: '2024-01-01T00:01:00.000',
          from: 'Chase',
          to: '+12025550123',
          body: 'Verify: 5678',
          status: 'failed',
        ),
      ];
      await settings.saveLogs(logs);

      final loaded = settings.forwardingLogs;
      expect(loaded.length, 2);
      expect(loaded[0].from, 'BofA');
      expect(loaded[0].status, 'sent');
      expect(loaded[1].from, 'Chase');
      expect(loaded[1].status, 'failed');
    });

    test('preserves order', () async {
      final settings = await SettingsService.load();
      final logs = [
        const LogEntry(time: 'first', from: 'A', to: 'to', body: 'b', status: 'sent'),
        const LogEntry(time: 'second', from: 'B', to: 'to', body: 'b', status: 'sent'),
      ];
      await settings.saveLogs(logs);

      final loaded = settings.forwardingLogs;
      expect(loaded[0].time, 'first');
      expect(loaded[1].time, 'second');
    });
  });

  group('SettingsService clearLogs', () {
    test('empties forwardingLogs', () async {
      final settings = await SettingsService.load();
      await settings.saveLogs([
        const LogEntry(time: 't', from: 'f', to: 'to', body: 'b', status: 'sent'),
      ]);
      await settings.clearLogs();
      expect(settings.forwardingLogs, isEmpty);
    });
  });
}
