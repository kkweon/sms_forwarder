import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../forwarding/sms_utils.dart';

const _forwardDedupKey = 'forward_dedup';

/// How long a (message body, destination) pair stays deduped. Matches the
/// Kotlin intake dedup TTL (`MessageNotificationListener.DEDUP_TTL_MS`).
const forwardDedupTtlMs = 5 * 60 * 1000;

/// Persists which (message body, destination) pairs have been forwarded
/// recently, so the same code is delivered to the same number at most once
/// within [forwardDedupTtlMs]. Mirrors [LoopDetector]'s SharedPreferences
/// pattern (prune on read and on write).
///
/// This is the cross-source dedup layer: an incoming SMS fires BOTH the
/// [SmsReceiver] and the Google Messages notification, a few seconds apart;
/// both feed the same Dart isolate. The persistent cache also survives a
/// process restart within the TTL. The in-process race between two
/// near-simultaneous events is closed by [ForwardReservation].
class ForwardDedupCache {
  final SharedPreferences _prefs;
  ForwardDedupCache._(this._prefs);

  static Future<ForwardDedupCache> load() async =>
      ForwardDedupCache._(await SharedPreferences.getInstance());

  /// The single source of truth for the dedup key. The body is normalized
  /// with [preprocessBody] (same normalization the keyword matcher and
  /// [forwardSms] apply) so a code with and without an SMS-Retriever `<#>`
  /// prefix dedups to the same key.
  static String keyFor(String body, String destination) =>
      '${preprocessBody(body).hashCode}|$destination';

  /// Keys forwarded within the TTL, pruned of stale entries.
  Set<String> get recentKeys {
    final cutoff = DateTime.now().millisecondsSinceEpoch - forwardDedupTtlMs;
    return _decode()
        .where((e) => e.timestampMs > cutoff)
        .map((e) => e.key)
        .toSet();
  }

  /// Records a successful forward of [key]. Prunes stale entries, then appends.
  Future<void> recordForward(String key, int timestampMs) async {
    final cutoff = timestampMs - forwardDedupTtlMs;
    final kept = _decode().where((e) => e.timestampMs > cutoff).toList()
      ..add(_Entry(key, timestampMs));
    await _prefs.setStringList(
      _forwardDedupKey,
      kept.map((e) => e.encode()).toList(),
    );
  }

  List<_Entry> _decode() {
    final raw = _prefs.getStringList(_forwardDedupKey) ?? [];
    return raw.map(_Entry.tryDecode).whereType<_Entry>().toList();
  }
}

class _Entry {
  final String key;
  final int timestampMs;
  const _Entry(this.key, this.timestampMs);

  String encode() => jsonEncode({'k': key, 't': timestampMs});

  static _Entry? tryDecode(String s) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return _Entry(m['k'] as String, (m['t'] as num).toInt());
    } catch (_) {
      return null;
    }
  }
}
