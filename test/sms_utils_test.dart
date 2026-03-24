import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/sms_utils.dart';

void main() {
  group('normalizePhone', () {
    test('10-digit US local gets +1 prefix', () {
      expect(normalizePhone('2025550123'), '+12025550123');
    });

    test('+1 US number stays the same', () {
      expect(normalizePhone('+12025550123'), '+12025550123');
    });

    test('10-digit local and +1 number normalize to same value (regression: duplicate bug)', () {
      expect(normalizePhone('2025550123'), equals(normalizePhone('+12025550123')));
    });

    test('strips formatting characters', () {
      expect(normalizePhone('(202) 555-0123'), '+12025550123');
      expect(normalizePhone('+1-202-555-0123'), '+12025550123');
    });

    test('11-digit number with leading 1 gets + prefix', () {
      expect(normalizePhone('12025550123'), '+12025550123');
    });

    test('international number gets + prefix', () {
      expect(normalizePhone('447911123456'), '+447911123456');
      expect(normalizePhone('+447911123456'), '+447911123456');
    });

    test('returns null for fewer than 7 digits', () {
      expect(normalizePhone('123456'), isNull);
      expect(normalizePhone(''), isNull);
      expect(normalizePhone('abc'), isNull);
    });
  });

  group('containsVerificationCode', () {
    test('matches standard OTP/verification messages', () {
      expect(containsVerificationCode('Your verification code is 123456'), isTrue);
      expect(containsVerificationCode('Your OTP is 5678'), isTrue);
      expect(containsVerificationCode('Use code 12345678 to verify'), isTrue);
      expect(containsVerificationCode('[AppName] Your code: 9012'), isTrue);
    });

    test('matches auth/confirm/pin/passcode keywords', () {
      expect(containsVerificationCode('Your auth code: 9876'), isTrue);
      expect(containsVerificationCode('Confirm with PIN 4321'), isTrue);
      expect(containsVerificationCode('Enter passcode 567890'), isTrue);
    });

    test('rejects messages with no keyword', () {
      expect(containsVerificationCode('Hello, how are you?'), isFalse);
      expect(containsVerificationCode('Your order #12345 has shipped'), isFalse);
      expect(containsVerificationCode('Meeting at 3pm tomorrow'), isFalse);
      expect(containsVerificationCode('Call me at 1234567'), isFalse);
    });

    test('rejects messages with keyword but no 4-8 digit number', () {
      expect(containsVerificationCode('Please verify your email'), isFalse);
      expect(containsVerificationCode('Enter your code'), isFalse);
      expect(containsVerificationCode('Auth required'), isFalse);
    });

    test('rejects empty string', () {
      expect(containsVerificationCode(''), isFalse);
    });

    test('rejects digit sequences outside 4-8 range', () {
      expect(containsVerificationCode('Your code is 123'), isFalse);
      expect(containsVerificationCode('Your code is 123456789'), isFalse);
    });
  });
}
