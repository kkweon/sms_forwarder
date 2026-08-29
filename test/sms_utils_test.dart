import 'package:flutter_test/flutter_test.dart';
import 'package:sms_forwarder/forwarding/sms_utils.dart';

void main() {
  group('preprocessBody', () {
    test('strips <#> prefix', () {
      expect(preprocessBody('<#>Hello world'), 'Hello world');
      expect(preprocessBody('Hello world'), 'Hello world');
    });

    test('strips trailing 11-char app hash', () {
      expect(preprocessBody('Code 1234. 3olHr09B9Po'), 'Code 1234.');
    });

    test('strips both prefix and hash', () {
      expect(
        preprocessBody('<#>BofA: Code 781265. 3olHr09B9Po'),
        'BofA: Code 781265.',
      );
    });

    test('no-op on plain messages', () {
      expect(preprocessBody('Your code is 1234'), 'Your code is 1234');
    });

    test('does not strip hash-like suffix that is not 11 chars', () {
      expect(preprocessBody('Code 1234. abc'), 'Code 1234. abc');
    });
  });

  group('normalizePhone', () {
    test('10-digit US local gets +1 prefix', () {
      expect(normalizePhone('2025550123'), '+12025550123');
    });

    test('+1 US number stays the same', () {
      expect(normalizePhone('+12025550123'), '+12025550123');
    });

    test(
      '10-digit local and +1 number normalize to same value (regression: duplicate bug)',
      () {
        expect(
          normalizePhone('2025550123'),
          equals(normalizePhone('+12025550123')),
        );
      },
    );

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

  group('containsVerificationCode — real OTP formats', () {
    test('matches standard numeric OTP messages', () {
      expect(
        containsVerificationCode('Your verification code is 123456'),
        isTrue,
      );
      expect(containsVerificationCode('Your OTP is 5678'), isTrue);
      expect(containsVerificationCode('Use code 12345678 to verify'), isTrue);
      expect(containsVerificationCode('[AppName] Your code: 9012'), isTrue);
      expect(containsVerificationCode('Your Chase code is 483920.'), isTrue);
    });

    test('matches auth/confirmation/pin/passcode phrasings', () {
      expect(containsVerificationCode('Your auth code: 9876'), isTrue);
      expect(containsVerificationCode('Confirm with PIN 4321'), isTrue);
      expect(containsVerificationCode('Enter passcode 567890'), isTrue);
      expect(containsVerificationCode('Your access code is 5150'), isTrue);
      expect(containsVerificationCode('Your login code: 8080'), isTrue);
      expect(
        containsVerificationCode('Your authentication code: 90210'),
        isTrue,
      );
      expect(
        containsVerificationCode('Your confirmation code is 4477'),
        isTrue,
      );
    });

    test('matches 2FA / two-factor / one-time phrasings', () {
      expect(containsVerificationCode('2FA code: 5150'), isTrue);
      expect(
        containsVerificationCode('Two-factor code 8899 for your account'),
        isTrue,
      );
      expect(containsVerificationCode('Your one-time code is A1B2C3'), isTrue);
      expect(
        containsVerificationCode(
          'Your one-time passcode is 9F2K1A. Valid 5 min.',
        ),
        isTrue,
      );
    });

    test('matches alphanumeric codes', () {
      expect(
        containsVerificationCode('Your verification code is: 2ECB89'),
        isTrue,
      );
      expect(containsVerificationCode('Your code is A1B2C3'), isTrue);
    });

    test('matches a code that PRECEDES the keyword', () {
      // "<code> is your <brand> code" — the code comes first, separated by a
      // whole clause, so the backward proximity window has to cover it.
      expect(containsVerificationCode('G-123456 is your Google code'), isTrue);
      expect(
        containsVerificationCode('G-123456 is your Google verification code.'),
        isTrue,
      );
      expect(containsVerificationCode('884412 is your Instagram code'), isTrue);
    });

    test('matches OTPs carrying marketing-ish boilerplate', () {
      // Real OTPs often end with STOP/unsubscribe or "save this" wording; a
      // blanket promo veto would wrongly drop these.
      expect(
        containsVerificationCode(
          'Your verification code is 483920. Reply STOP to unsubscribe.',
        ),
        isTrue,
      );
      expect(
        containsVerificationCode(
          'Your code is 774213. Save this message for your records.',
        ),
        isTrue,
      );
      expect(
        containsVerificationCode(
          'Verification code 552310 for your account. '
          'Msg&data rates may apply.',
        ),
        isTrue,
      );
    });

    test('matches GEICO alphanumeric code message (regression)', () {
      expect(
        containsVerificationCode(
          'GEICO: Your verification code is: 2ECB89. It expires in 10 '
          'minutes. Please do not share this code with anyone or reply to '
          'this message.',
        ),
        isTrue,
      );
    });

    test('matches BofA SMS Retriever format message (regression)', () {
      expect(
        containsVerificationCode(
          "<#>BofA: DO NOT share this Sign In code. We will NEVER call you or "
          "text you for it. Code 781265. Reply HELP if you didn't request it. "
          "3olHr09B9Po",
        ),
        isTrue,
      );
    });
  });

  group('containsVerificationCode — rejects non-OTP messages', () {
    test('rejects messages with no keyword at all', () {
      expect(containsVerificationCode('Hello, how are you?'), isFalse);
      expect(
        containsVerificationCode('Your order #12345 has shipped'),
        isFalse,
      );
      expect(containsVerificationCode('Meeting at 3pm tomorrow'), isFalse);
      expect(containsVerificationCode('Call me at 1234567'), isFalse);
      expect(
        containsVerificationCode('Your Amazon package 7742 was delivered.'),
        isFalse,
      );
      expect(
        containsVerificationCode(
          'Copy that. Meeting moved to 1430 in room B204.',
        ),
        isFalse,
      );
    });

    test('rejects a keyword hiding INSIDE another word', () {
      // The old matcher was substring-based, so every one of these was
      // forwarded: 'pin' in shopping/spinning, 'auth' in author,
      // 'code' in Decode/barcode.
      expect(
        containsVerificationCode('Your shopping order 84213 ships Sept 2.'),
        isFalse,
      );
      expect(
        containsVerificationCode(
          'I was spinning at the gym, burned 1250 calories.',
        ),
        isFalse,
      );
      expect(
        containsVerificationCode('The author of that book wrote 1984.'),
        isFalse,
      );
      expect(
        containsVerificationCode('Decode the barcode 55213 on the box.'),
        isFalse,
      );
    });

    test('rejects ordinary confirmation messages', () {
      // Bare 'confirm' is not a keyword; only 'confirmation code' is.
      expect(
        containsVerificationCode(
          'Your reservation is confirmed. Ref A19B, table for 4.',
        ),
        isFalse,
      );
      expect(
        containsVerificationCode('Order confirmed! #38221 ships Thursday.'),
        isFalse,
      );
      expect(
        containsVerificationCode(
          'Appointment confirmed for 10/15, clinic room 2B14.',
        ),
        isFalse,
      );
      expect(
        containsVerificationCode('Flight confirmed: UA482 departs 0730.'),
        isFalse,
      );
    });

    test('rejects a weak keyword sitting far from any code', () {
      expect(
        containsVerificationCode(
          'Your new debit card PIN mailer 8842 was sent by post.',
        ),
        isFalse,
      );
      expect(
        containsVerificationCode('Area code 415 numbers, call 5551234 back.'),
        isFalse,
      );
    });

    test('rejects bare auth/verify wording with no code', () {
      expect(containsVerificationCode('Please verify your email'), isFalse);
      expect(containsVerificationCode('Enter your code'), isFalse);
      expect(containsVerificationCode('Auth required'), isFalse);
      expect(
        containsVerificationCode('auth service down, ticket 88213 filed.'),
        isFalse,
      );
    });

    test('rejects empty string', () {
      expect(containsVerificationCode(''), isFalse);
    });

    test('rejects tokens outside the 4-8 character range', () {
      expect(containsVerificationCode('Your code is 123'), isFalse);
      expect(containsVerificationCode('Your code is 123456789'), isFalse);
      expect(containsVerificationCode('Your code is A1B'), isFalse);
      expect(containsVerificationCode('Your code is A1B2C3D4E5'), isFalse);
    });
  });

  group('containsVerificationCode — known limitations', () {
    // These are false positives the matcher still lets through: the word
    // 'code'/'pin' is genuinely adjacent to a code-shaped token, so no
    // amount of proximity tuning separates them from a real OTP. Pinned
    // here so a future change to the rules shows up as a deliberate diff
    // rather than a silent behavior change.
    test('promo codes are still forwarded', () {
      expect(
        containsVerificationCode(
          'Use code SAVE20 for 20% off your next order!',
        ),
        isTrue,
      );
      expect(
        containsVerificationCode('FLASH SALE: promo code BOGO50 ends tonight.'),
        isTrue,
      );
    });

    test('non-OTP senses of "code" adjacent to a number are forwarded', () {
      expect(
        containsVerificationCode(
          'Package shipped to zip code 94107, arrives Tue.',
        ),
        isTrue,
      );
      expect(
        containsVerificationCode('Error code 0x80 on build 4412, see logs.'),
        isTrue,
      );
    });

    test('non-OTP sense of "pin" adjacent to a number is forwarded', () {
      expect(
        containsVerificationCode(
          'Bowling: I got a 7-10 split, pin 1092 knocked down.',
        ),
        isTrue,
      );
    });

    test('a coupon code longer than 8 chars is skipped only by luck', () {
      // 'WELCOME15' is 9 characters, so the length bound rejects it. Nothing
      // about it being promotional is detected.
      expect(
        containsVerificationCode('Your coupon code WELCOME15 is ready.'),
        isFalse,
      );
    });
  });
}
