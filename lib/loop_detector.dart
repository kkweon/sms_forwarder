import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

class LoopDetector {
  final SharedPreferences _prefs;
  LoopDetector._(this._prefs);

  static Future<LoopDetector> load() async =>
      LoopDetector._(await SharedPreferences.getInstance());

  bool get detected => _prefs.getBool(prefsLoopDetected) ?? false;

  /// Counts this forward toward the rate limit.
  /// Returns true if the limit was exceeded (loop detected).
  /// Calls [onLoopDetected] when the threshold is breached.
  Future<bool> countForward({
    required Future<void> Function() onLoopDetected,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - loopWindowMs;
    final raw = _prefs.getStringList(recentForwardsKey) ?? [];
    final recent = raw
        .map((s) => int.tryParse(s) ?? 0)
        .where((ts) => ts > cutoff)
        .toList();
    if (recent.length >= loopThreshold) {
      await _prefs.setBool(prefsLoopDetected, true);
      await _prefs.remove(recentForwardsKey);
      debugPrint('[SMS] Loop detected (${recent.length} forwards in ${loopWindowMs ~/ 1000}s)');
      await onLoopDetected();
      return true;
    }
    recent.add(now);
    await _prefs.setStringList(
      recentForwardsKey,
      recent.map((ts) => ts.toString()).toList(),
    );
    return false;
  }

  Future<void> reset() async {
    await _prefs.setBool(prefsLoopDetected, false);
    await _prefs.remove(recentForwardsKey);
  }
}
