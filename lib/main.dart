import 'package:flutter/material.dart';

import 'app_log.dart';
import 'file_logger.dart';
import 'sms_forwarder_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = await FileLogger.init();
  initAppLog(logger);
  appLog('[SMS] app started');
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
