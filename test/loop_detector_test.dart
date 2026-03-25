import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/loop_detector.dart';

// The threshold check is `recent.length >= 5` *before* adding the current
// call, so the loop is detected on the 6th forward (or on any call when
// 5+ recent timestamps are already in prefs).

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LoopDetector detected getter', () {
    test('returns false by default', () async {
      final detector = await LoopDetector.load();
      expect(detector.detected, isFalse);
    });

    test('returns true when loop_detected flag is preset in prefs', () async {
      SharedPreferences.setMockInitialValues({'loop_detected': true});
      final detector = await LoopDetector.load();
      expect(detector.detected, isTrue);
    });
  });

  group('LoopDetector countForward', () {
    test('returns false and does not trigger callback on first forward', () async {
      var callbackCalled = false;
      final detector = await LoopDetector.load();
      final result = await detector.countForward(
        onLoopDetected: () async => callbackCalled = true,
      );
      expect(result, isFalse);
      expect(callbackCalled, isFalse);
    });

    test('returns false for five consecutive forwards (below threshold)', () async {
      final detector = await LoopDetector.load();
      for (var i = 0; i < 5; i++) {
        final result = await detector.countForward(onLoopDetected: () async {});
        expect(result, isFalse);
      }
    });

    test('returns true and calls onLoopDetected when 5 recent entries are already in prefs', () async {
      // Pre-seed 5 recent timestamps so the next call sees >= threshold.
      final prefs = await SharedPreferences.getInstance();
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setStringList('recent_forwards', [ts, ts, ts, ts, ts]);

      var callbackCalled = false;
      final detector = await LoopDetector.load();
      final result = await detector.countForward(
        onLoopDetected: () async => callbackCalled = true,
      );
      expect(result, isTrue);
      expect(callbackCalled, isTrue);
    });

    test('sets detected flag after threshold breach', () async {
      final prefs = await SharedPreferences.getInstance();
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setStringList('recent_forwards', [ts, ts, ts, ts, ts]);

      final detector = await LoopDetector.load();
      await detector.countForward(onLoopDetected: () async {});
      expect(detector.detected, isTrue);
    });

    test('clears recent_forwards list after threshold breach', () async {
      final prefs = await SharedPreferences.getInstance();
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setStringList('recent_forwards', [ts, ts, ts, ts, ts]);

      final detector = await LoopDetector.load();
      await detector.countForward(onLoopDetected: () async {});
      expect(prefs.getStringList('recent_forwards'), isNull);
    });

    test('prunes entries older than 60 seconds', () async {
      // Pre-seed 5 old timestamps — all will be pruned, so count stays at 1.
      final prefs = await SharedPreferences.getInstance();
      final old = (DateTime.now().millisecondsSinceEpoch - 61 * 1000).toString();
      await prefs.setStringList('recent_forwards', [old, old, old, old, old]);

      var callbackCalled = false;
      final detector = await LoopDetector.load();
      final result = await detector.countForward(
        onLoopDetected: () async => callbackCalled = true,
      );

      // After pruning, only the 1 new entry exists → below threshold.
      expect(result, isFalse);
      expect(callbackCalled, isFalse);
    });

    test('counts only recent entries toward threshold', () async {
      // 5 stale + 5 recent → after pruning, 5 recent entries remain → triggers.
      final prefs = await SharedPreferences.getInstance();
      final old = (DateTime.now().millisecondsSinceEpoch - 61 * 1000).toString();
      final recent = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setStringList(
        'recent_forwards',
        [old, old, old, old, old, recent, recent, recent, recent, recent],
      );

      var callbackCalled = false;
      final detector = await LoopDetector.load();
      final result = await detector.countForward(
        onLoopDetected: () async => callbackCalled = true,
      );

      expect(result, isTrue);
      expect(callbackCalled, isTrue);
    });
  });

  group('LoopDetector reset', () {
    test('clears detected flag', () async {
      SharedPreferences.setMockInitialValues({'loop_detected': true});
      final detector = await LoopDetector.load();
      await detector.reset();
      expect(detector.detected, isFalse);
    });

    test('clears recent_forwards list', () async {
      final prefs = await SharedPreferences.getInstance();
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setStringList('recent_forwards', [ts]);

      final detector = await LoopDetector.load();
      await detector.reset();

      expect(prefs.getStringList('recent_forwards'), isNull);
    });
  });
}
