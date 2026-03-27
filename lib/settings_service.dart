import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'log_entry.dart';

const _prefsForwardingEnabled = 'forwarding_enabled';
const _prefsDestinationNumbers = 'destination_numbers';
const _prefsForwardingLog = 'forwarding_log';

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

  /// Returns log entries newest-first.
  List<LogEntry> get forwardingLogs {
    final raw = _prefs.getStringList(_prefsForwardingLog) ?? [];
    return raw
        .map((e) => LogEntry.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  // --- Writes ---

  Future<void> setForwardingEnabled(bool value) =>
      _prefs.setBool(_prefsForwardingEnabled, value);

  Future<void> setDestinationNumbers(List<String> numbers) =>
      _prefs.setStringList(_prefsDestinationNumbers, numbers);

  /// Saves [logs] to persistent storage (newest-first order).
  Future<void> saveLogs(List<LogEntry> logs) => _prefs.setStringList(
    _prefsForwardingLog,
    logs.map((e) => jsonEncode(e.toJson())).toList(),
  );

  Future<void> clearLogs() => _prefs.remove(_prefsForwardingLog);
}
