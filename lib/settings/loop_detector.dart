import 'package:shared_preferences/shared_preferences.dart';

const _recentForwardsKey = 'recent_forwards';
const _prefsLoopDetected = 'loop_detected';
const _loopWindowMs = 60 * 1000;

/// Persists the rolling list of recent forward attempt timestamps and the
/// "loop detected" UI flag. Decision logic lives in [planForSms]; this
/// class only reads and writes.
class LoopDetector {
  final SharedPreferences _prefs;
  LoopDetector._(this._prefs);

  static Future<LoopDetector> load() async =>
      LoopDetector._(await SharedPreferences.getInstance());

  bool get detected => _prefs.getBool(_prefsLoopDetected) ?? false;

  /// Timestamps within the loop-detection window, pruned of stale entries.
  List<int> get recentTimestamps {
    final raw = _prefs.getStringList(_recentForwardsKey) ?? [];
    final cutoff = DateTime.now().millisecondsSinceEpoch - _loopWindowMs;
    return raw
        .map((s) => int.tryParse(s) ?? 0)
        .where((t) => t > cutoff)
        .toList();
  }

  /// Appends [timestampMs] to the recent-forwards list.
  Future<void> recordAttempt(int timestampMs) async {
    final cutoff = timestampMs - _loopWindowMs;
    final raw = _prefs.getStringList(_recentForwardsKey) ?? [];
    final recent =
        raw.map((s) => int.tryParse(s) ?? 0).where((t) => t > cutoff).toList()
          ..add(timestampMs);
    await _prefs.setStringList(
      _recentForwardsKey,
      recent.map((ts) => ts.toString()).toList(),
    );
  }

  /// Flags the loop and clears recent timestamps. Called from the handler
  /// when [DisableForwardingCommand] fires.
  Future<void> markLoopDetected() async {
    await _prefs.setBool(_prefsLoopDetected, true);
    await _prefs.remove(_recentForwardsKey);
  }

  Future<void> reset() async {
    await _prefs.setBool(_prefsLoopDetected, false);
    await _prefs.remove(_recentForwardsKey);
  }
}
