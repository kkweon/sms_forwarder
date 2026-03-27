import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

const _recentForwardsKey = 'recent_forwards';
const _loopWindowMs = 60 * 1000; // 60 seconds
const _loopThreshold = 5;
const _prefsLoopDetected = 'loop_detected';

class LoopDetector {
  final SharedPreferences _prefs;
  LoopDetector._(this._prefs);

  static Future<LoopDetector> load() async =>
      LoopDetector._(await SharedPreferences.getInstance());

  bool get detected => _prefs.getBool(_prefsLoopDetected) ?? false;

  /// Counts this forward toward the rate limit.
  /// Returns true if the limit was exceeded (loop detected).
  /// Calls [onLoopDetected] when the threshold is breached.
  Future<bool> countForward({
    required Future<void> Function() onLoopDetected,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _loopWindowMs;
    final raw = _prefs.getStringList(_recentForwardsKey) ?? [];
    final recent = raw
        .map((s) => int.tryParse(s) ?? 0)
        .where((ts) => ts > cutoff)
        .toList();
    if (recent.length >= _loopThreshold) {
      await _prefs.setBool(_prefsLoopDetected, true);
      await _prefs.remove(_recentForwardsKey);
      appLog('[SMS] Loop detected (${recent.length} forwards in ${_loopWindowMs ~/ 1000}s)');
      await onLoopDetected();
      return true;
    }
    recent.add(now);
    await _prefs.setStringList(
      _recentForwardsKey,
      recent.map((ts) => ts.toString()).toList(),
    );
    return false;
  }

  Future<void> reset() async {
    await _prefs.setBool(_prefsLoopDetected, false);
    await _prefs.remove(_recentForwardsKey);
  }
}
