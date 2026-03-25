import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/services.dart';

import 'sms_service.dart';

/// Production [SmsService] backed by the native EventChannel (for receiving)
/// and a [Telephony] instance (for sending).
///
/// Pass [telephony] explicitly to use [Telephony.backgroundInstance] in
/// background isolates; omit to default to [Telephony.instance].
class RealSmsService implements SmsService {
  static const _eventChannel =
      EventChannel('dev.kkweon.sms_forwarder/sms_events');

  final Telephony _telephony;
  StreamSubscription<dynamic>? _sub;

  RealSmsService({Telephony? telephony})
      : _telephony = telephony ?? Telephony.instance;

  @override
  void startListening(void Function(SmsMessage) onMessage) {
    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        onMessage(SmsMessage(
          address: event['address'] as String?,
          body: event['body'] as String?,
        ));
      }
    });
  }

  @override
  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

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
