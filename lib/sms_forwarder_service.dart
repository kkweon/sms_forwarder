import 'dart:async';

import 'package:another_telephony/telephony.dart';

import 'app_log.dart';
import 'log_entry.dart';
import 'loop_detector.dart';
import 'real_sms_service.dart';
import 'settings_service.dart';
import 'sms_service.dart';
import 'sms_utils.dart';

const maxLogEntries = 50;
const _sendTimeoutSeconds = 30;

/// Sends [message] to all [destinationNumbers] and returns a log entry per recipient.
/// Callers are responsible for checking forwarding_enabled, keyword matching,
/// and loop detection before calling this function.
Future<List<LogEntry>> forwardSms({
  required SmsService smsService,
  required SmsMessage message,
  required List<String> destinationNumbers,
}) async {
  final body = preprocessBody(message.body ?? '');
  final from = message.address ?? 'unknown';
  final forwardText = 'Fwd from $from:\n$body';
  final now = DateTime.now().toIso8601String();

  final pendingEntries = <String, LogEntry>{};
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
        pendingEntries[number] = LogEntry(
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
          pendingEntries[e.key] = LogEntry(
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

  return pendingEntries.values.toList();
}

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  appLog(
    '[SMS] BG handler fired: from=${message.address} body=${message.body}',
  );
  try {
    final settings = await SettingsService.load();
    if (!settings.forwardingEnabled) {
      appLog('[SMS] BG: forwarding disabled, skipping');
      return;
    }
    final body = preprocessBody(message.body ?? '');
    if (!containsVerificationCode(body)) {
      appLog('[SMS] BG: no keyword match, skipping. body="$body"');
      return;
    }
    final numbers = settings.destinationNumbers;
    if (numbers.isEmpty) {
      appLog('[SMS] BG: no destination numbers, skipping');
      return;
    }
    final loopDetector = await LoopDetector.load();
    if (await loopDetector.countForward(
      onLoopDetected: () => settings.setForwardingEnabled(false),
    )) {
      appLog('[SMS] BG: loop detected, aborting forward');
      return;
    }
    appLog('[SMS] BG: forwarding to $numbers');
    final newEntries = await forwardSms(
      smsService: RealSmsService(telephony: Telephony.backgroundInstance),
      message: message,
      destinationNumbers: numbers,
    );
    final logs = [
      ...newEntries,
      ...settings.forwardingLogs,
    ].take(maxLogEntries).toList();
    await settings.saveLogs(logs);
    appLog('[SMS] BG: done, ${newEntries.length} entries logged');
  } catch (e, stack) {
    appLog('[SMS] BG ERROR in backgroundMessageHandler: $e\n$stack');
  }
}
