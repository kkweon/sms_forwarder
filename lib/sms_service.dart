import 'package:another_telephony/telephony.dart';

/// Abstraction over SMS sending so the UI can be tested without real hardware.
abstract class SmsService {
  Future<void> sendSms({
    required String to,
    required String message,
    bool isMultipart = false,
    required void Function(SendStatus) statusListener,
  });
}
