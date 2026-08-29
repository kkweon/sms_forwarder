const keywords = ['verif', 'code', 'otp', 'passcode', 'pin', 'auth', 'confirm'];

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

bool containsVerificationCode(String text) {
  final cleaned = preprocessBody(text);
  if (cleaned.isEmpty) return false;
  final hasKeyword = RegExp(
    keywords.join('|'),
    caseSensitive: false,
  ).hasMatch(cleaned);
  final hasCode = _codeToken.hasMatch(cleaned);
  return hasKeyword && hasCode;
}

String formatTime(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
