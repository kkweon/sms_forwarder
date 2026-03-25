import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/log_entry.dart';

void main() {
  const entry = LogEntry(
    time: '2024-01-01T00:00:00.000',
    from: 'BofA',
    to: '+12025550123',
    body: 'Code 1234.',
    status: 'sent',
  );

  group('LogEntry toJson / fromJson round-trip', () {
    test('sent', () {
      final result = LogEntry.fromJson(entry.toJson());
      expect(result.time, entry.time);
      expect(result.from, entry.from);
      expect(result.to, entry.to);
      expect(result.body, entry.body);
      expect(result.status, entry.status);
    });

    test('failed', () {
      const e = LogEntry(time: 't', from: 'f', to: 'to', body: 'b', status: 'failed');
      expect(LogEntry.fromJson(e.toJson()).status, 'failed');
    });

    test('timeout', () {
      const e = LogEntry(time: 't', from: 'f', to: 'to', body: 'b', status: 'timeout');
      expect(LogEntry.fromJson(e.toJson()).status, 'timeout');
    });
  });

  group('LogEntry toJson', () {
    test('produces expected keys and values', () {
      final json = entry.toJson();
      expect(json.keys, containsAll(['time', 'from', 'to', 'body', 'status']));
      expect(json['time'], entry.time);
      expect(json['from'], entry.from);
      expect(json['to'], entry.to);
      expect(json['body'], entry.body);
      expect(json['status'], entry.status);
    });
  });

  group('LogEntry failed getter', () {
    test('returns false for sent', () {
      expect(entry.failed, isFalse);
    });

    test('returns true for failed', () {
      const e = LogEntry(time: 't', from: 'f', to: 'to', body: 'b', status: 'failed');
      expect(e.failed, isTrue);
    });

    test('returns true for timeout', () {
      const e = LogEntry(time: 't', from: 'f', to: 'to', body: 'b', status: 'timeout');
      expect(e.failed, isTrue);
    });
  });
}
