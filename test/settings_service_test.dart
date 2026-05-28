import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/settings/forward_event.dart';
import 'package:sms_forwarder/settings/settings_service.dart';

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

  group('SettingsService forwardEvents', () {
    test('returns empty list by default', () async {
      final settings = await SettingsService.load();
      expect(settings.forwardEvents, isEmpty);
    });

    test('returns deserialized events after recordForwardEvents()', () async {
      final settings = await SettingsService.load();
      await settings.recordForwardEvents([
        const ForwardEvent(
          time: '2024-01-01T00:00:00.000',
          from: 'BofA',
          to: '+12025550123',
          body: 'Code 1234.',
          status: 'sent',
        ),
        const ForwardEvent(
          time: '2024-01-01T00:01:00.000',
          from: 'Chase',
          to: '+12025550123',
          body: 'Verify: 5678',
          status: 'failed',
        ),
      ]);

      final loaded = settings.forwardEvents;
      expect(loaded.length, 2);
      expect(loaded[0].from, 'BofA');
      expect(loaded[0].status, 'sent');
      expect(loaded[1].from, 'Chase');
      expect(loaded[1].status, 'failed');
    });

    test('prepends new events newest-first across multiple calls', () async {
      final settings = await SettingsService.load();
      await settings.recordForwardEvents([
        const ForwardEvent(
          time: 'first',
          from: 'A',
          to: 'to',
          body: 'b',
          status: 'sent',
        ),
      ]);
      await settings.recordForwardEvents([
        const ForwardEvent(
          time: 'second',
          from: 'B',
          to: 'to',
          body: 'b',
          status: 'sent',
        ),
      ]);

      final loaded = settings.forwardEvents;
      expect(loaded[0].time, 'second');
      expect(loaded[1].time, 'first');
    });

    test('caps history at 50 events', () async {
      final settings = await SettingsService.load();
      for (var i = 0; i < 60; i++) {
        await settings.recordForwardEvents([
          ForwardEvent(
            time: '$i',
            from: 'A',
            to: 'to',
            body: 'b',
            status: 'sent',
          ),
        ]);
      }
      expect(settings.forwardEvents.length, 50);
      expect(settings.forwardEvents.first.time, '59');
    });
  });

  group('SettingsService clearForwardEvents', () {
    test('empties forwardEvents', () async {
      final settings = await SettingsService.load();
      await settings.recordForwardEvents([
        const ForwardEvent(
          time: 't',
          from: 'f',
          to: 'to',
          body: 'b',
          status: 'sent',
        ),
      ]);
      await settings.clearForwardEvents();
      expect(settings.forwardEvents, isEmpty);
    });
  });
}
