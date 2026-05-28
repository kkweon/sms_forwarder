import 'package:flutter/services.dart';

import 'incoming_message.dart';

const _eventChannelName = 'dev.kkweon.sms_forwarder/notifications';
const _controlChannelName = 'dev.kkweon.sms_forwarder/notifications/control';

/// Dart-side facade for the platform channels owned by
/// `MessageNotificationListener.kt`:
///
/// - An [EventChannel] streams parsed notifications as [IncomingMessage]s.
/// - A [MethodChannel] exposes permission helpers and a debug-only test
///   notification poster.
class NotificationBridge {
  static final NotificationBridge instance = NotificationBridge._(
    const EventChannel(_eventChannelName),
    const MethodChannel(_controlChannelName),
  );

  final EventChannel _events;
  final MethodChannel _control;
  Stream<IncomingMessage>? _stream;

  NotificationBridge._(this._events, this._control);

  /// Broadcast stream of notifications matching the listener's whitelist.
  /// The Kotlin service buffers a small number of events that arrive
  /// before Dart subscribes, so cold-start messages are not dropped.
  Stream<IncomingMessage> get stream {
    return _stream ??= _events.receiveBroadcastStream().map(
      (e) => IncomingMessage.fromMap(e as Map<dynamic, dynamic>),
    );
  }

  Future<bool> isAccessGranted() async {
    final r = await _control.invokeMethod<bool>('isAccessGranted');
    return r ?? false;
  }

  Future<void> openSettings() => _control.invokeMethod<void>('openSettings');

  /// Posts a real MessagingStyle notification from our own package so the
  /// end-to-end pipeline can be exercised on-device without sending an
  /// SMS. The listener bypasses the package whitelist just for this single
  /// post.
  Future<void> postTestNotification() =>
      _control.invokeMethod<void>('postTestNotification');
}
