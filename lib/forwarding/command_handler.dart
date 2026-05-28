import '../logging/app_log.dart';
import '../settings/loop_detector.dart';
import '../settings/settings_service.dart';
import 'command.dart';
import 'sms_sender.dart';
import 'sms_service.dart';

/// Side-effecting layer: executes one [Command] decided by [planForSms].
class CommandHandler {
  final SmsService smsService;
  final SettingsService settings;
  final LoopDetector loopDetector;

  CommandHandler({
    required this.smsService,
    required this.settings,
    required this.loopDetector,
  });

  Future<void> handle(Command cmd) async {
    appLog('[SMS] BG: ${cmd.log}');
    switch (cmd) {
      case NoActionCommand():
        break;
      case DisableForwardingCommand():
        await settings.setForwardingEnabled(false);
        await loopDetector.markLoopDetected();
      case ForwardCommand(
        :final message,
        :final destinations,
        :final attemptTimestampMs,
      ):
        await loopDetector.recordAttempt(attemptTimestampMs);
        final events = await forwardSms(
          smsService: smsService,
          message: message,
          destinationNumbers: destinations,
        );
        await settings.recordForwardEvents(events);
        appLog('[SMS] BG: done, ${events.length} events logged');
    }
  }
}
