import 'package:another_telephony/telephony.dart';

import 'sms_service.dart';

/// Production [SmsService] backed by a [Telephony] instance for sending.
///
/// Pass [telephony] explicitly to use [Telephony.backgroundInstance] in
/// background isolates; omit to default to [Telephony.instance].
class RealSmsService implements SmsService {
  final Telephony _telephony;

  RealSmsService({Telephony? telephony})
    : _telephony = telephony ?? Telephony.instance;

  @override
  Future<void> sendSms({
    required String to,
    required String message,
    bool isMultipart = false,
    required void Function(SendStatus) statusListener,
  }) {
    return _telephony.sendSms(
      to: to,
      message: message,
      isMultipart: isMultipart,
      statusListener: statusListener,
    );
  }
}
