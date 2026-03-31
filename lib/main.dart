import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'file_logger.dart';
import 'sms_forwarder_service.dart';
import 'sms_forwarder_page.dart';
import 'sms_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = await FileLogger.init();
  initAppLog(logger);
  appLog('[SMS] app started');
  runApp(MyApp(logger: logger));
}

/// Entry point for the headless [FlutterEngine] started by [SmsReceiver.kt].
///
/// Must live in main.dart (the root Dart library) so that the 2-argument
/// [DartEntrypoint] can resolve it by name without a library URI.
@pragma('vm:entry-point')
Future<void> backgroundSmsEntryPoint() async {
  dev.log('[SMS] backgroundSmsEntryPoint: entered', name: 'SmsForwarder');
  try {
    WidgetsFlutterBinding.ensureInitialized();
    dev.log('[SMS] backgroundSmsEntryPoint: binding ok', name: 'SmsForwarder');
    final logger = await FileLogger.init();
    initAppLog(logger);
    dev.log('[SMS] backgroundSmsEntryPoint: logger ok', name: 'SmsForwarder');
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('pending_bg_sms_address');
    final body = prefs.getString('pending_bg_sms_body');
    await prefs.remove('pending_bg_sms_address');
    await prefs.remove('pending_bg_sms_body');
    if (body == null || body.isEmpty) {
      appLog('[SMS] backgroundSmsEntryPoint: no pending SMS found');
      return;
    }
    appLog('[SMS] backgroundSmsEntryPoint: from=$address body=$body');
    await backgroundMessageHandler(
      makeSmsMessage(address: address, body: body),
    );
  } catch (e, stack) {
    dev.log('[SMS] BG CRASH: $e\n$stack', name: 'SmsForwarder');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.logger});

  final FileLogger logger;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS Forwarder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: SmsForwarderPage(logger: logger),
    );
  }
}
