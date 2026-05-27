import 'package:another_telephony/telephony.dart';

import 'sms_service.dart';

/// Production [SmsService] backed by [Telephony.instance] for outgoing
/// sends. All forwarding now runs in the main isolate (hosted by the
/// notification-listener service's cached FlutterEngine), so there is no
/// separate background instance to choose between.
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
