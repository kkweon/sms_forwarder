import 'app_state.dart';
import 'command.dart';
import 'incoming_message.dart';
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

  return ForwardCommand(
    message: msg,
    destinations: state.destinationNumbers,
    attemptTimestampMs: nowMs,
    log: 'forwarding to ${state.destinationNumbers}',
  );
}
