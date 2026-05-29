import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/forwarding/forward_reservation.dart';
import 'package:sms_forwarder/settings/forward_dedup_cache.dart';

void main() {
  setUp(ForwardReservation.reset);

  test('first claim of a key succeeds', () {
    expect(ForwardReservation.tryClaim('k1', 1000), isTrue);
  });

  test('immediate re-claim of the same key fails', () {
    expect(ForwardReservation.tryClaim('k1', 1000), isTrue);
    expect(ForwardReservation.tryClaim('k1', 1001), isFalse);
  });

  test('different keys are independent', () {
    expect(ForwardReservation.tryClaim('k1', 1000), isTrue);
    expect(ForwardReservation.tryClaim('k2', 1000), isTrue);
  });

  test('claim can be re-acquired after release (failure retry path)', () {
    expect(ForwardReservation.tryClaim('k1', 1000), isTrue);
    ForwardReservation.release('k1');
    expect(ForwardReservation.tryClaim('k1', 1002), isTrue);
  });

  test('claim expires after the TTL', () {
    expect(ForwardReservation.tryClaim('k1', 1000), isTrue);
    // Just past the TTL window — a fresh claim should win again.
    expect(ForwardReservation.tryClaim('k1', 1000 + forwardDedupTtlMs), isTrue);
  });

  test('claim still blocks just inside the TTL', () {
    expect(ForwardReservation.tryClaim('k1', 1000), isTrue);
    expect(
      ForwardReservation.tryClaim('k1', 1000 + forwardDedupTtlMs - 1),
      isFalse,
    );
  });
}
