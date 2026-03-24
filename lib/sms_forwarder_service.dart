import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:another_telephony/telephony.dart';

import 'log_entry.dart';
import 'loop_detector.dart';
import 'settings_service.dart';
import 'sms_utils.dart';

const maxLogEntries = 50;
const _sendTimeoutSeconds = 30;

/// Sends [message] to all [destinationNumbers] and returns a log entry per recipient.
/// Callers are responsible for checking forwarding_enabled, keyword matching,
/// and loop detection before calling this function.
Future<List<LogEntry>> forwardSms({
  required Telephony telephony,
  required SmsMessage message,
  required List<String> destinationNumbers,
}) async {
  final body = message.body ?? '';
  final from = message.address ?? 'unknown';
  final forwardText = 'Fwd from $from:\n$body';
  final now = DateTime.now().toIso8601String();

  final pendingEntries = <String, LogEntry>{};
  final completers = <String, Completer<void>>{};

  for (final number in destinationNumbers) {
    final completer = Completer<void>();
    completers[number] = completer;
    await telephony.sendSms(
      to: number,
      message: forwardText,
      isMultipart: true,
      statusListener: (SendStatus status) {
        debugPrint('[SMS] send to $number status=$status');
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

  await Future.wait(completers.entries.map((e) => e.value.future.timeout(
    Duration(seconds: _sendTimeoutSeconds),
    onTimeout: () {
      debugPrint('[SMS] timeout waiting for status from ${e.key}');
      pendingEntries[e.key] = LogEntry(
        time: now,
        from: from,
        to: e.key,
        body: body,
        status: 'timeout',
      );
    },
  )));

  return pendingEntries.values.toList();
}

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  debugPrint('[SMS] BG handler fired: from=${message.address} body=${message.body}');
  final settings = await SettingsService.load();
  if (!settings.forwardingEnabled) {
    debugPrint('[SMS] BG: forwarding disabled, skipping');
    return;
  }
  final body = message.body ?? '';
  if (!containsVerificationCode(body)) {
    debugPrint('[SMS] BG: no keyword match, skipping');
    return;
  }
  final numbers = settings.destinationNumbers;
  if (numbers.isEmpty) {
    debugPrint('[SMS] BG: no destination numbers, skipping');
    return;
  }
  final loopDetector = await LoopDetector.load();
  if (await loopDetector.countForward(
    onLoopDetected: () => settings.setForwardingEnabled(false),
  )) {
    debugPrint('[SMS] BG: loop detected, aborting forward');
    return;
  }
  debugPrint('[SMS] BG: forwarding to $numbers');
  final newEntries = await forwardSms(
    telephony: Telephony.backgroundInstance,
    message: message,
    destinationNumbers: numbers,
  );
  final logs = [...newEntries, ...settings.forwardingLogs]
      .take(maxLogEntries)
      .toList();
  await settings.saveLogs(logs);
}
