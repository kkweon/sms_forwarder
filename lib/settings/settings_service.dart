import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'forward_event.dart';

const _prefsForwardingEnabled = 'forwarding_enabled';
const _prefsDestinationNumbers = 'destination_numbers';
// Prefs key kept as 'forwarding_log' to avoid migrating existing users.
const _prefsForwardEvents = 'forwarding_log';
const _maxForwardEvents = 50;

class SettingsService {
  final SharedPreferences _prefs;
  SettingsService._(this._prefs);

  static Future<SettingsService> load() async =>
      SettingsService._(await SharedPreferences.getInstance());

  // --- Reads ---

  bool get forwardingEnabled =>
      _prefs.getBool(_prefsForwardingEnabled) ?? false;

  List<String> get destinationNumbers =>
      _prefs.getStringList(_prefsDestinationNumbers) ?? [];

  /// Newest-first list of per-recipient forward outcomes.
  List<ForwardEvent> get forwardEvents {
    final raw = _prefs.getStringList(_prefsForwardEvents) ?? [];
    return raw
        .map(
          (e) => ForwardEvent.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
  }

  // --- Writes ---

  Future<void> setForwardingEnabled(bool value) =>
      _prefs.setBool(_prefsForwardingEnabled, value);

  Future<void> setDestinationNumbers(List<String> numbers) =>
      _prefs.setStringList(_prefsDestinationNumbers, numbers);

  /// Prepends [newEvents] to the persisted history, capped at the most
  /// recent [_maxForwardEvents].
  Future<void> recordForwardEvents(List<ForwardEvent> newEvents) {
    final merged = [
      ...newEvents,
      ...forwardEvents,
    ].take(_maxForwardEvents).toList();
    return _prefs.setStringList(
      _prefsForwardEvents,
      merged.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> clearForwardEvents() => _prefs.remove(_prefsForwardEvents);

  /// Re-reads SharedPreferences from disk, picking up writes made by the
  /// background headless FlutterEngine since this instance was last loaded.
  Future<void> reload() => _prefs.reload();
}
