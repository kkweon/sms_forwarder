import 'package:flutter/material.dart';

import 'forwarding/platform_sms_service.dart';
import 'logging/app_log.dart';
import 'logging/file_logger.dart';
import 'notifications/notification_bridge.dart';
import 'notifications/notification_dispatcher.dart';
import 'ui/sms_forwarder_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = await FileLogger.init();
  initAppLog(logger);
  appLog('[SMS] app started');
  final dispatcher = NotificationDispatcher(
    streamFactory: () => NotificationBridge.instance.stream,
    smsServiceFactory: () => PlatformSmsService(),
  );
  await dispatcher.start();
  runApp(MyApp(logger: logger));
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
