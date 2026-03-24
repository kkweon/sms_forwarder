import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'sms_utils.dart';

/// Sends [message] to all [destinationNumbers] and returns log entries.
/// Callers are responsible for checking forwarding_enabled, keyword matching,
/// and loop detection before calling this function.
Future<List<Map<String, dynamic>>> forwardSms({
  required Telephony telephony,
  required SmsMessage message,
  required List<String> destinationNumbers,
}) async {
  final body = message.body ?? '';
  final from = message.address ?? 'unknown';
  final forwardText = 'Fwd from $from:\n$body';
  final now = DateTime.now().toIso8601String();

  final pendingEntries = <String, Map<String, dynamic>>{};
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
        pendingEntries[number] = {
          'time': now,
          'from': from,
          'to': number,
          'body': body,
          'status': status == SendStatus.SENT ? 'sent' : 'failed',
        };
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  await Future.wait(completers.entries.map((e) => e.value.future.timeout(
    Duration(seconds: sendTimeoutSeconds),
    onTimeout: () {
      debugPrint('[SMS] timeout waiting for status from ${e.key}');
      pendingEntries[e.key] = {
        'time': now,
        'from': from,
        'to': e.key,
        'body': body,
        'status': 'timeout',
      };
    },
  )));

  return pendingEntries.values.toList();
}

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  debugPrint('[SMS] BG handler fired: from=${message.address} body=${message.body}');
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(prefsForwardingEnabled) ?? false)) {
    debugPrint('[SMS] BG: forwarding disabled, skipping');
    return;
  }
  final body = message.body ?? '';
  if (!containsVerificationCode(body)) {
    debugPrint('[SMS] BG: no keyword match, skipping');
    return;
  }
  final numbers = prefs.getStringList(prefsDestinationNumbers) ?? [];
  if (numbers.isEmpty) {
    debugPrint('[SMS] BG: no destination numbers, skipping');
    return;
  }
  if (await checkLoopAndTrack(prefs)) {
    debugPrint('[SMS] BG: loop detected, aborting forward');
    return;
  }
  debugPrint('[SMS] BG: forwarding to $numbers');
  final entries = await forwardSms(
    telephony: Telephony.backgroundInstance,
    message: message,
    destinationNumbers: numbers,
  );
  final log = prefs.getStringList(prefsForwardingLog) ?? [];
  for (final entry in entries) {
    log.insert(0, jsonEncode(entry));
  }
  if (log.length > maxLogEntries) log.removeRange(maxLogEntries, log.length);
  await prefs.setStringList(prefsForwardingLog, log);
}
