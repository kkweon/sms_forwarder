import 'package:another_telephony/telephony.dart';
import 'package:sms_forwarder/sms_service.dart';

class RecordedSend {
  final String to;
  final String message;
  RecordedSend(this.to, this.message);
}

/// Fake [SmsService] for tests.
///
/// Inspect [sent] to verify outgoing SMS sends.
/// Pass [statusToReport] to simulate send failures.
class FakeSmsService implements SmsService {
  final List<RecordedSend> sent = [];
  final SendStatus statusToReport;

  FakeSmsService({this.statusToReport = SendStatus.SENT});

  @override
  Future<void> sendSms({
    required String to,
    required String message,
    bool isMultipart = false,
    required void Function(SendStatus) statusListener,
  }) async {
    sent.add(RecordedSend(to, message));
    statusListener(statusToReport);
  }
}
