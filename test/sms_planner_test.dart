import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/app_state.dart';
import 'package:sms_forwarder/command.dart';
import 'package:sms_forwarder/sms_planner.dart';
import 'package:sms_forwarder/sms_utils.dart';

AppState _state({
  bool forwardingEnabled = true,
  List<String> destinationNumbers = const ['+12025550123'],
  List<int> recentForwardTimestampsMs = const [],
}) => AppState(
  forwardingEnabled: forwardingEnabled,
  destinationNumbers: destinationNumbers,
  recentForwardTimestampsMs: recentForwardTimestampsMs,
);

void main() {
  final validSms = makeSmsMessage(address: 'BofA', body: 'Your code is 123456');
  final now = DateTime(2026, 1, 1, 12, 0, 0);
  final nowMs = now.millisecondsSinceEpoch;

  group('planForSms — skip branches return NoActionCommand', () {
    test('forwarding disabled', () {
      final cmd = planForSms(
        validSms,
        _state(forwardingEnabled: false),
        now: now,
      );
      expect(cmd, isA<NoActionCommand>());
      expect(cmd.log, contains('forwarding disabled'));
    });

    test('no keyword match', () {
      final cmd = planForSms(
        makeSmsMessage(address: 'X', body: 'See you at 7pm'),
        _state(),
        now: now,
      );
      expect(cmd, isA<NoActionCommand>());
      expect(cmd.log, contains('no keyword match'));
    });

    test('no destination numbers', () {
      final cmd = planForSms(
        validSms,
        _state(destinationNumbers: []),
        now: now,
      );
      expect(cmd, isA<NoActionCommand>());
      expect(cmd.log, contains('no destination numbers'));
    });
  });

  group('planForSms — loop detection', () {
    test('5 recent forwards triggers DisableForwardingCommand', () {
      final cmd = planForSms(
        validSms,
        _state(recentForwardTimestampsMs: List.filled(5, nowMs - 1000)),
        now: now,
      );
      expect(cmd, isA<DisableForwardingCommand>());
      expect(cmd.log, contains('loop detected'));
    });

    test('4 recent forwards stays under threshold and forwards', () {
      final cmd = planForSms(
        validSms,
        _state(recentForwardTimestampsMs: List.filled(4, nowMs - 1000)),
        now: now,
      );
      expect(cmd, isA<ForwardCommand>());
    });

    test('stale timestamps (outside window) do not count', () {
      final stale = nowMs - (61 * 1000);
      final cmd = planForSms(
        validSms,
        _state(recentForwardTimestampsMs: List.filled(10, stale)),
        now: now,
      );
      expect(cmd, isA<ForwardCommand>());
    });
  });

  group('planForSms — happy path', () {
    test('returns ForwardCommand with destinations and timestamp', () {
      final cmd = planForSms(
        validSms,
        _state(destinationNumbers: ['+12025550123', '+19998887777']),
        now: now,
      );
      expect(cmd, isA<ForwardCommand>());
      final fwd = cmd as ForwardCommand;
      expect(fwd.destinations, ['+12025550123', '+19998887777']);
      expect(fwd.attemptTimestampMs, nowMs);
      expect(fwd.message, validSms);
    });
  });
}
