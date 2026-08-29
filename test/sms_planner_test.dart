import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/forwarding/command.dart';
import 'package:sms_forwarder/forwarding/sms_planner.dart';
import 'package:sms_forwarder/notifications/incoming_message.dart';
import 'package:sms_forwarder/settings/app_state.dart';
import 'package:sms_forwarder/settings/forward_dedup_cache.dart';

AppState _state({
  bool forwardingEnabled = true,
  List<String> destinationNumbers = const ['+12025550123'],
  List<int> recentForwardTimestampsMs = const [],
  Set<String> recentForwardDedupKeys = const {},
}) => AppState(
  forwardingEnabled: forwardingEnabled,
  destinationNumbers: destinationNumbers,
  recentForwardTimestampsMs: recentForwardTimestampsMs,
  recentForwardDedupKeys: recentForwardDedupKeys,
);

IncomingMessage _msg({String? address, String? body}) =>
    IncomingMessage(address: address, body: body);

void main() {
  final validSms = _msg(address: 'BofA', body: 'Your code is 123456');
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
        _msg(address: 'X', body: 'See you at 7pm'),
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

  group('planForSms — per-destination dedup filter', () {
    test('drops a destination already forwarded for this body', () {
      final cmd = planForSms(
        validSms,
        _state(
          destinationNumbers: ['+12025550123', '+19998887777'],
          recentForwardDedupKeys: {
            ForwardDedupCache.keyFor(validSms.body!, '+12025550123'),
          },
        ),
        now: now,
      );
      expect(cmd, isA<ForwardCommand>());
      expect((cmd as ForwardCommand).destinations, ['+19998887777']);
    });

    test('NoActionCommand when all destinations already forwarded', () {
      final cmd = planForSms(
        validSms,
        _state(
          destinationNumbers: ['+12025550123', '+19998887777'],
          recentForwardDedupKeys: {
            ForwardDedupCache.keyFor(validSms.body!, '+12025550123'),
            ForwardDedupCache.keyFor(validSms.body!, '+19998887777'),
          },
        ),
        now: now,
      );
      expect(cmd, isA<NoActionCommand>());
      expect(cmd.log, contains('already forwarded'));
    });

    test('a different code to the same destination is not deduped', () {
      final cmd = planForSms(
        _msg(address: 'BofA', body: 'Your code is 654321'),
        _state(
          recentForwardDedupKeys: {
            ForwardDedupCache.keyFor('Your code is 123456', '+12025550123'),
          },
        ),
        now: now,
      );
      expect(cmd, isA<ForwardCommand>());
    });
  });

  group('planForSms — real-world message regressions', () {
    test('GEICO alphanumeric code reaches ForwardCommand', () {
      final cmd = planForSms(
        _msg(
          address: '94067',
          body:
              'GEICO: Your verification code is: 2ECB89. It expires in 10 '
              'minutes. Please do not share this code with anyone or reply '
              'to this message.',
        ),
        _state(),
        now: now,
      );
      expect(cmd, isA<ForwardCommand>(), reason: 'log was: ${cmd.log}');
    });
  });
}
