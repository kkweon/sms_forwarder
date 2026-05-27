import 'dart:async';

import 'package:another_telephony/telephony.dart';

import 'app_log.dart';
import 'app_state.dart';
import 'command_handler.dart';
import 'forward_event.dart';
import 'loop_detector.dart';
import 'real_sms_service.dart';
import 'settings_service.dart';
import 'sms_planner.dart';
import 'sms_service.dart';
import 'sms_utils.dart';

const _sendTimeoutSeconds = 30;

/// Sends [message] to all [destinationNumbers] and returns a [ForwardEvent]
/// per recipient. Callers are responsible for checking forwarding_enabled,
/// keyword matching, and loop detection before calling this function.
Future<List<ForwardEvent>> forwardSms({
  required SmsService smsService,
  required SmsMessage message,
  required List<String> destinationNumbers,
}) async {
  final body = preprocessBody(message.body ?? '');
  final from = message.address ?? 'unknown';
  final forwardText = 'Fwd from $from:\n$body';
  final now = DateTime.now().toIso8601String();

  final pendingEvents = <String, ForwardEvent>{};
  final completers = <String, Completer<void>>{};

  for (final number in destinationNumbers) {
    final completer = Completer<void>();
    completers[number] = completer;
    await smsService.sendSms(
      to: number,
      message: forwardText,
      isMultipart: true,
      statusListener: (SendStatus status) {
        appLog('[SMS] send to $number status=$status');
        pendingEvents[number] = ForwardEvent(
          time: now,
          from: from,
          to: number,
          body: body,
          status: status == SendStatus.SENT ? 'sent' : 'failed',
        );
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  await Future.wait(
    completers.entries.map(
      (e) => e.value.future.timeout(
        Duration(seconds: _sendTimeoutSeconds),
        onTimeout: () {
          appLog('[SMS] timeout waiting for status from ${e.key}');
          pendingEvents[e.key] = ForwardEvent(
            time: now,
            from: from,
            to: e.key,
            body: body,
            status: 'timeout',
          );
        },
      ),
    ),
  );

  return pendingEvents.values.toList();
}

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  appLog(
    '[SMS] BG handler fired: from=${message.address} body=${message.body}',
  );
  try {
    final settings = await SettingsService.load();
    final loopDetector = await LoopDetector.load();
    final state = AppState(
      forwardingEnabled: settings.forwardingEnabled,
      destinationNumbers: settings.destinationNumbers,
      recentForwardTimestampsMs: loopDetector.recentTimestamps,
    );
    final handler = CommandHandler(
      smsService: RealSmsService(telephony: Telephony.backgroundInstance),
      settings: settings,
      loopDetector: loopDetector,
    );
    await handler.handle(planForSms(message, state));
  } catch (e, stack) {
    appLog('[SMS] BG ERROR in backgroundMessageHandler: $e\n$stack');
  }
}
