import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/settings/forward_dedup_cache.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ForwardDedupCache.keyFor', () {
    test('combines preprocessed-body hash and destination', () {
      final key = ForwardDedupCache.keyFor('Your code is 123456', '+1555');
      expect(key, '${'Your code is 123456'.hashCode}|+1555');
    });

    test('is stable for the same body + destination', () {
      expect(
        ForwardDedupCache.keyFor('Code 999', '+1555'),
        ForwardDedupCache.keyFor('Code 999', '+1555'),
      );
    });

    test('normalizes the <#> SMS-Retriever prefix and 11-char hash suffix', () {
      // preprocessBody strips a leading "<#>" and a trailing app-hash token,
      // so these two dedup to the same key.
      expect(
        ForwardDedupCache.keyFor('<#> Your code is 123456 FA9qCX9VSuz', '+1'),
        ForwardDedupCache.keyFor('Your code is 123456', '+1'),
      );
    });

    test('different destinations produce different keys', () {
      expect(
        ForwardDedupCache.keyFor('Code 1', '+1555'),
        isNot(ForwardDedupCache.keyFor('Code 1', '+1666')),
      );
    });
  });

  group('recentKeys / recordForward', () {
    test('is empty by default', () async {
      final cache = await ForwardDedupCache.load();
      expect(cache.recentKeys, isEmpty);
    });

    test('contains a key after recordForward', () async {
      final cache = await ForwardDedupCache.load();
      final now = DateTime.now().millisecondsSinceEpoch;
      await cache.recordForward('hash|+1555', now);

      final reloaded = await ForwardDedupCache.load();
      expect(reloaded.recentKeys, contains('hash|+1555'));
    });

    test('prunes entries older than the TTL on read', () async {
      final prefs = await SharedPreferences.getInstance();
      final stale =
          DateTime.now().millisecondsSinceEpoch - forwardDedupTtlMs - 1;
      await prefs.setStringList('forward_dedup', [
        '{"k":"hash|+1555","t":$stale}',
      ]);

      final cache = await ForwardDedupCache.load();
      expect(cache.recentKeys, isEmpty);
    });

    test('prunes stale entries while appending', () async {
      final prefs = await SharedPreferences.getInstance();
      final stale =
          DateTime.now().millisecondsSinceEpoch - forwardDedupTtlMs - 1;
      await prefs.setStringList('forward_dedup', ['{"k":"old|+1","t":$stale}']);

      final now = DateTime.now().millisecondsSinceEpoch;
      final cache = await ForwardDedupCache.load();
      await cache.recordForward('fresh|+2', now);

      expect(cache.recentKeys, {'fresh|+2'});
    });

    test('ignores malformed entries', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('forward_dedup', ['not json', '{"oops":1}']);

      final cache = await ForwardDedupCache.load();
      expect(cache.recentKeys, isEmpty);
    });
  });
}
