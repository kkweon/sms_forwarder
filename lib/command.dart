import 'package:another_telephony/telephony.dart';

/// What the planner decides to do for a single incoming SMS.
/// Every command carries the [log] string the handler should write
/// before/while executing it.
sealed class Command {
  final String log;
  const Command(this.log);
}

/// The SMS matched all filters; forward it to [destinations] and record
/// the attempt timestamp in the loop detector.
class ForwardCommand extends Command {
  final SmsMessage message;
  final List<String> destinations;
  final int attemptTimestampMs;
  const ForwardCommand({
    required this.message,
    required this.destinations,
    required this.attemptTimestampMs,
    required String log,
  }) : super(log);
}

/// Too many forwards in the loop-detector window. Disable forwarding and
/// raise the loop-detected flag so the UI can prompt the user.
class DisableForwardingCommand extends Command {
  const DisableForwardingCommand(super.log);
}

/// The SMS did not match (forwarding off, no keyword, no destinations).
/// Carries the reason for the debug log; no side effects.
class NoActionCommand extends Command {
  const NoActionCommand(super.log);
}
