/// Human-readable summary of what [containsVerificationCode] looks for,
/// shown in the UI's "Detection Keywords" card. The regexes below are the
/// source of truth for matching; this list is kept in sync by hand.
const keywords = [
  'verification',
  'OTP',
  'passcode',
  '2FA',
  'two-factor',
  'security code',
  'one-time code',
  'access code',
  'login code',
  'sign-in code',
  'authentication code',
  'confirmation code',
  'code / PIN next to a code',
];

/// Normalizes a phone number to E.164-like form for consistent storage and comparison.
/// Returns null if the input has fewer than 7 digits.
/// 10-digit numbers are assumed to be US local and get a +1 prefix.
/// All other numbers get a + prefix (stripping any existing leading +).
String? normalizePhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length < 7) return null;
  if (digits.length == 10) return '+1$digits';
  return '+$digits';
}

/// Strips Android SMS Retriever API formatting from a message body:
/// removes the leading `<#>` prefix and any trailing 11-character app hash.
String preprocessBody(String body) {
  var s = body.startsWith('<#>') ? body.substring(3) : body;
  s = s.replaceFirst(RegExp(r'\s+\w{11}$'), '');
  return s.trim();
}

/// A plausible verification code: a 4-8 character run of letters and digits
/// containing at least one digit. Alphanumeric codes (GEICO's `2ECB89`,
/// Google's `G-123456`) are as common as all-digit ones, so both must match.
final _codeToken = RegExp(r'\b(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{4,8}\b');

/// Phrases specific enough to mark a message as an OTP on their own.
///
/// Word-anchored, unlike the old substring match — that one fired `pin`
/// inside `shopping`, `auth` inside `author` and `code` inside `Decode`,
/// forwarding ordinary texts.
final _strongPhrase = RegExp(
  r'\b(?:verif\w*|otp\b|passcodes?\b|2fa\b|two[-\s]?factor\b'
  r'|(?:security|one[-\s]?time|access|login|sign[-\s]?in|authentication'
  r'|confirmation|auth)\s+codes?\b)',
  caseSensitive: false,
);

/// Words too common to stand alone ("Order confirmed! #38221", "the door
/// code? I think it's 4821"). They only count when a [_codeToken] sits right
/// beside them.
///
/// Proximity separates them from a real OTP only when the number is some
/// distance away. A non-OTP number that happens to be adjacent ("zip code
/// 94107", "Error code 0x80") still matches — see the known-limitation
/// group in `test/sms_utils_test.dart`.
final _weakKeyword = RegExp(r'\b(?:pins?|codes?)\b', caseSensitive: false);

/// Gap allowed between a [_weakKeyword] and its code, in characters.
///
/// Asymmetric on purpose. A code *following* the word is nearly adjacent
/// ("code is 1234", "code: 9012"), so a tight window rejects "PIN mailer
/// 8842". A code *preceding* it is separated by a whole clause
/// ("G-123456 is your Google code"), so that direction needs more room.
const _weakGapAfterKeyword = 6;
const _weakGapBeforeKeyword = 20;

bool containsVerificationCode(String text) {
  final cleaned = preprocessBody(text);
  if (cleaned.isEmpty) return false;

  final codes = _codeToken.allMatches(cleaned).toList();
  if (codes.isEmpty) return false;
  if (_strongPhrase.hasMatch(cleaned)) return true;

  for (final keyword in _weakKeyword.allMatches(cleaned)) {
    for (final code in codes) {
      final after = code.start - keyword.end;
      if (after >= 0 && after <= _weakGapAfterKeyword) return true;
      final before = keyword.start - code.end;
      if (before >= 0 && before <= _weakGapBeforeKeyword) return true;
    }
  }
  return false;
}

String formatTime(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
