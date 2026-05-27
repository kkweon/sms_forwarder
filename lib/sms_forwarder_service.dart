import 'dart:async';

import 'package:another_telephony/telephony.dart' show SendStatus;

import 'app_log.dart';
import 'forward_event.dart';
import 'incoming_message.dart';
import 'sms_service.dart';
import 'sms_utils.dart';

const _sendTimeoutSeconds = 30;

/// Sends [message] to all [destinationNumbers] and returns a [ForwardEvent]
/// per recipient. Callers are responsible for checking forwarding_enabled,
/// keyword matching, and loop detection before calling this function.
Future<List<ForwardEvent>> forwardSms({
  required SmsService smsService,
  required IncomingMessage message,
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
