import '../notifications/incoming_message.dart';
import '../settings/app_state.dart';
import '../settings/forward_dedup_cache.dart';
import 'command.dart';
import 'sms_utils.dart';

const loopWindowMs = 60 * 1000;
const loopThreshold = 5;

/// Pure decision function: given an incoming message and a snapshot of app
/// state, return the single [Command] the handler should execute.
///
/// No I/O, no clock unless [now] is omitted (in which case `DateTime.now()`
/// is read). Pass [now] from tests for deterministic behavior.
Command planForSms(IncomingMessage msg, AppState state, {DateTime? now}) {
  if (!state.forwardingEnabled) {
    return const NoActionCommand('forwarding disabled, skipping');
  }
  final body = preprocessBody(msg.body ?? '');
  if (!containsVerificationCode(body)) {
    return NoActionCommand('no keyword match, skipping. body="$body"');
  }
  if (state.destinationNumbers.isEmpty) {
    return const NoActionCommand('no destination numbers, skipping');
  }

  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final cutoff = nowMs - loopWindowMs;
  final recent = state.recentForwardTimestampsMs
      .where((t) => t > cutoff)
      .toList();
  if (recent.length >= loopThreshold) {
    return DisableForwardingCommand(
      'loop detected (${recent.length} forwards in ${loopWindowMs ~/ 1000}s), disabling',
    );
  }

  // Drop destinations this exact body was already forwarded to within the
  // dedup TTL (cross-source + cross-restart). The handler's synchronous
  // ForwardReservation closes the remaining in-process race.
  final remaining = state.destinationNumbers
      .where(
        (d) => !state.recentForwardDedupKeys.contains(
          ForwardDedupCache.keyFor(msg.body ?? '', d),
        ),
      )
      .toList();
  if (remaining.isEmpty) {
    return const NoActionCommand(
      'already forwarded this message to all destinations, skipping',
    );
  }

  return ForwardCommand(
    message: msg,
    destinations: remaining,
    attemptTimestampMs: nowMs,
    log: 'forwarding to $remaining',
  );
}
