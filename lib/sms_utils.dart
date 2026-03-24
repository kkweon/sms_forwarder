import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

/// Normalizes a phone number to E.164-like form for consistent storage and comparison.
/// Returns null if the input has fewer than 7 digits.
/// 10-digit numbers are assumed to be US local and get a +1 prefix.
/// All other numbers get a + prefix (stripping any existing leading +).
String? normalizePhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length < 7) return null;
  if (digits.length == 10) return '+1$digits';
  return '+$digits';
}

bool containsVerificationCode(String text) {
  if (text.isEmpty) return false;
  final hasKeyword = RegExp(
    keywords.join('|'),
    caseSensitive: false,
  ).hasMatch(text);
  final hasDigits = RegExp(r'\b\d{4,8}\b').hasMatch(text);
  return hasKeyword && hasDigits;
}

/// Tracks this forward and returns true if a loop/rate-limit is detected.
/// On detection, sets forwarding_enabled=false and loop_detected=true in prefs.
Future<bool> checkLoopAndTrack(SharedPreferences prefs) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final cutoff = now - loopWindowMs;
  final raw = prefs.getStringList(recentForwardsKey) ?? [];
  final recent = raw
      .map((s) => int.tryParse(s) ?? 0)
      .where((ts) => ts > cutoff)
      .toList();
  if (recent.length >= loopThreshold) {
    await prefs.setBool(prefsForwardingEnabled, false);
    await prefs.setBool(prefsLoopDetected, true);
    await prefs.remove(recentForwardsKey);
    debugPrint('[SMS] Loop detected (${recent.length} forwards in ${loopWindowMs ~/ 1000}s), disabling forwarding');
    return true;
  }
  recent.add(now);
  await prefs.setStringList(recentForwardsKey, recent.map((ts) => ts.toString()).toList());
  return false;
}

String formatTime(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
