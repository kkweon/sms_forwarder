import 'package:another_telephony/telephony.dart';

/// Abstraction over SMS send/receive so the UI can be tested without real hardware.
abstract class SmsService {
  void startListening(void Function(SmsMessage) onMessage);
  void stopListening();
  Future<void> sendSms({
    required String to,
    required String message,
    bool isMultipart = false,
    required void Function(SendStatus) statusListener,
  });
}
