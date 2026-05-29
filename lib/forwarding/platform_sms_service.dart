import 'package:another_telephony/telephony.dart' show SendStatus;
import 'package:flutter/services.dart';

import 'sms_service.dart';

/// [SmsService] backed by a MethodChannel that the listener service's
/// FlutterEngine wires up directly (see Kotlin `SmsSenderChannel`).
///
/// Replaces `another_telephony`'s `Telephony.sendSms`, whose
/// `plugins.shounakmulay.com/foreground_sms_channel` handler is registered
/// via the `ActivityAware` lifecycle and disappears as soon as
/// `MainActivity` is destroyed (e.g. when the user swipes the app away).
/// Our own channel is attached to the listener service's cached engine in
/// `MessageNotificationListener.ensureEngine`, so it survives the Activity
/// going away.
class PlatformSmsService implements SmsService {
  static const _defaultChannel = MethodChannel('dev.kkweon.sms_forwarder/sms');

  final MethodChannel _channel;

  PlatformSmsService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  @override
  Future<void> sendSms({
    required String to,
    required String message,
    bool isMultipart = false,
    required void Function(SendStatus) statusListener,
  }) async {
    SendStatus status;
    try {
      final result = await _channel.invokeMethod<String>('sendMultipartSms', {
        'to': to,
        'message': message,
      });
      status = result == 'sent' ? SendStatus.SENT : SendStatus.DELIVERED;
    } catch (_) {
      // Platform side errored, channel missing, etc. — surface as a
      // non-SENT status so `forwardSms` records 'failed' rather than
      // crashing the dispatcher.
      status = SendStatus.DELIVERED;
    }
    statusListener(status);
  }
}
