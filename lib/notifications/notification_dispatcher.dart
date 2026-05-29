import 'dart:async';

import '../forwarding/command_handler.dart';
import '../forwarding/sms_planner.dart';
import '../forwarding/sms_service.dart';
import '../logging/app_log.dart';
import '../settings/app_state.dart';
import '../settings/loop_detector.dart';
import '../settings/settings_service.dart';
import 'incoming_message.dart';

typedef IncomingStreamFactory = Stream<IncomingMessage> Function();
typedef SmsServiceFactory = SmsService Function();

/// Subscribes to a stream of incoming messages (in production, from
/// [NotificationBridge]) for the process lifetime and pipes each event
/// through [planForSms] → [CommandHandler].
///
/// Stateless aside from the active stream subscription — every event
/// reloads [SettingsService] + [LoopDetector] so writes made by the UI
/// are picked up immediately.
class NotificationDispatcher {
  NotificationDispatcher({
    required IncomingStreamFactory streamFactory,
    required SmsServiceFactory smsServiceFactory,
  }) : _streamFactory = streamFactory,
       _smsServiceFactory = smsServiceFactory;

  final IncomingStreamFactory _streamFactory;
  final SmsServiceFactory _smsServiceFactory;
  StreamSubscription<IncomingMessage>? _sub;

  Future<void> start() async {
    await _sub?.cancel();
    _sub = _streamFactory().listen(
      _handle,
      onError: (Object e, StackTrace s) => appLog('[NL] stream error: $e\n$s'),
    );
    appLog('[NL] dispatcher subscribed');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _handle(IncomingMessage msg) async {
    if (msg.diag != null) {
      appLog(
        '[NL] dropped: ${msg.diag} pkg=${msg.packageName} '
        'key=${msg.notificationKey}',
      );
      return;
    }
    appLog(
      '[NL] event from=${msg.address} pkg=${msg.packageName} body=${msg.body}',
    );
    try {
      final settings = await SettingsService.load();
      await settings.reload();
      final loopDetector = await LoopDetector.load();
      final state = AppState(
        forwardingEnabled: settings.forwardingEnabled,
        destinationNumbers: settings.destinationNumbers,
        recentForwardTimestampsMs: loopDetector.recentTimestamps,
      );
      final handler = CommandHandler(
        smsService: _smsServiceFactory(),
        settings: settings,
        loopDetector: loopDetector,
      );
      await handler.handle(planForSms(msg, state));
    } catch (e, stack) {
      appLog('[NL] handler crash: $e\n$stack');
    }
  }
}
