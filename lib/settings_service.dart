import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'log_entry.dart';

class SettingsService {
  final SharedPreferences _prefs;
  SettingsService._(this._prefs);

  static Future<SettingsService> load() async =>
      SettingsService._(await SharedPreferences.getInstance());

  // --- Reads ---

  bool get forwardingEnabled => _prefs.getBool(prefsForwardingEnabled) ?? false;

  List<String> get destinationNumbers =>
      _prefs.getStringList(prefsDestinationNumbers) ?? [];

  /// Returns log entries newest-first.
  List<LogEntry> get forwardingLogs {
    final raw = _prefs.getStringList(prefsForwardingLog) ?? [];
    return raw
        .map((e) => LogEntry.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  // --- Writes ---

  Future<void> setForwardingEnabled(bool value) =>
      _prefs.setBool(prefsForwardingEnabled, value);

  Future<void> setDestinationNumbers(List<String> numbers) =>
      _prefs.setStringList(prefsDestinationNumbers, numbers);

  /// Saves [logs] to persistent storage (newest-first order).
  Future<void> saveLogs(List<LogEntry> logs) => _prefs.setStringList(
        prefsForwardingLog,
        logs.map((e) => jsonEncode(e.toJson())).toList(),
      );

  Future<void> clearLogs() => _prefs.remove(prefsForwardingLog);
}
