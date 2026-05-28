import 'package:flutter/services.dart';

class TelephonyBridge {
  static final TelephonyBridge instance = TelephonyBridge._();
  TelephonyBridge._();

  static const _channel = MethodChannel('dev.kkweon.sms_forwarder/telephony');

  Future<List<String>> getOwnPhoneNumbers() async =>
      await _channel.invokeListMethod<String>('getOwnPhoneNumbers') ?? const [];
}
