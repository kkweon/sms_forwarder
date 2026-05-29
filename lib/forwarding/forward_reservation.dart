import 'package:flutter/foundation.dart';

import '../settings/forward_dedup_cache.dart' show forwardDedupTtlMs;

/// Process-wide, synchronous guard that closes the double-fire race.
///
/// An incoming SMS feeds the same Dart isolate from two sources (the
/// [SmsReceiver] and the Google Messages notification) a few seconds apart.
/// Each event's handler does several `await`s (loading settings, the dedup
/// cache, …) before sending, so two events can both read an empty persistent
/// snapshot and both send. [tryClaim] does a check-and-set with **no `await`
/// between the read and the write**, so the single-threaded event loop cannot
/// interleave two claims of the same key — exactly one wins.
///
/// In-memory only (lost on process restart); the persistent
/// [ForwardDedupCache] provides dedup across restarts. Both use the same
/// `bodyHash|destination` key from [ForwardDedupCache.keyFor].
class ForwardReservation {
  ForwardReservation._();

  static final Map<String, int> _claims = {};

  /// Atomically claims [key]. Returns true if the caller now owns the send;
  /// false if a live (within-TTL) claim already exists. There is intentionally
  /// no `await` between reading and writing `_claims`.
  static bool tryClaim(String key, int nowMs) {
    // Opportunistic prune (cheap; the map is tiny on a personal device).
    _claims.removeWhere((_, ts) => nowMs - ts >= forwardDedupTtlMs);
    final prev = _claims[key];
    if (prev != null && nowMs - prev < forwardDedupTtlMs) return false;
    _claims[key] = nowMs;
    return true;
  }

  /// Releases a claim so a later attempt can retry — used when a send fails or
  /// times out (the persistent cache is only written on success).
  static void release(String key) => _claims.remove(key);

  @visibleForTesting
  static void reset() => _claims.clear();
}
