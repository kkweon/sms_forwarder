import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/loop_detector.dart';

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

  group('LoopDetector recentTimestamps', () {
    test('returns empty by default', () async {
      final detector = await LoopDetector.load();
      expect(detector.recentTimestamps, isEmpty);
    });

    test('returns timestamps recorded within the window', () async {
      final detector = await LoopDetector.load();
      final now = DateTime.now().millisecondsSinceEpoch;
      await detector.recordAttempt(now);
      await detector.recordAttempt(now + 1);
      expect(detector.recentTimestamps.length, 2);
    });

    test('prunes timestamps older than 60 seconds', () async {
      final prefs = await SharedPreferences.getInstance();
      final old = (DateTime.now().millisecondsSinceEpoch - 61 * 1000)
          .toString();
      await prefs.setStringList('recent_forwards', [old, old, old]);

      final detector = await LoopDetector.load();
      expect(detector.recentTimestamps, isEmpty);
    });
  });

  group('LoopDetector recordAttempt', () {
    test('appends a timestamp', () async {
      final detector = await LoopDetector.load();
      final now = DateTime.now().millisecondsSinceEpoch;
      await detector.recordAttempt(now);
      await detector.recordAttempt(now + 5);

      final reloaded = await LoopDetector.load();
      expect(reloaded.recentTimestamps, containsAll([now, now + 5]));
    });

    test('prunes stale entries while appending', () async {
      final prefs = await SharedPreferences.getInstance();
      final old = (DateTime.now().millisecondsSinceEpoch - 61 * 1000)
          .toString();
      await prefs.setStringList('recent_forwards', [old, old]);

      final now = DateTime.now().millisecondsSinceEpoch;
      final detector = await LoopDetector.load();
      await detector.recordAttempt(now);

      expect(detector.recentTimestamps, [now]);
    });
  });

  group('LoopDetector markLoopDetected', () {
    test('sets detected flag', () async {
      final detector = await LoopDetector.load();
      await detector.markLoopDetected();
      expect(detector.detected, isTrue);
    });

    test('clears recent_forwards', () async {
      final prefs = await SharedPreferences.getInstance();
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setStringList('recent_forwards', [ts, ts]);

      final detector = await LoopDetector.load();
      await detector.markLoopDetected();
      expect(prefs.getStringList('recent_forwards'), isNull);
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
