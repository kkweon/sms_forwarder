import '../logging/app_log.dart';
import '../settings/forward_dedup_cache.dart';
import '../settings/loop_detector.dart';
import '../settings/settings_service.dart';
import 'command.dart';
import 'forward_reservation.dart';
import 'sms_sender.dart';
import 'sms_service.dart';

/// Side-effecting layer: executes one [Command] decided by [planForSms].
class CommandHandler {
  final SmsService smsService;
  final SettingsService settings;
  final LoopDetector loopDetector;
  final ForwardDedupCache dedupCache;

  CommandHandler({
    required this.smsService,
    required this.settings,
    required this.loopDetector,
    required this.dedupCache,
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

        final now = DateTime.now().millisecondsSinceEpoch;
        // Synchronously claim each destination (the loop runs to completion
        // with no `await` between tryClaim's read and write, so a concurrent
        // event for the same SMS sees these claims and backs off). Only
        // destinations we win the claim for are sent.
        final claimed = destinations
            .where(
              (d) => ForwardReservation.tryClaim(
                ForwardDedupCache.keyFor(message.body ?? '', d),
                now,
              ),
            )
            .toList();
        if (claimed.isEmpty) {
          appLog(
            '[SMS] BG: all destinations already reserved by a concurrent event, skipping',
          );
          break;
        }

        final events = await forwardSms(
          smsService: smsService,
          message: message,
          destinationNumbers: claimed,
        );

        // Record dedup ONLY for successful sends; release the claim on
        // failure/timeout so a later attempt can retry. Every event is logged
        // regardless of status (below).
        for (final e in events) {
          final key = ForwardDedupCache.keyFor(message.body ?? '', e.to);
          if (e.status == 'sent') {
            await dedupCache.recordForward(key, now);
          } else {
            ForwardReservation.release(key);
          }
        }

        await settings.recordForwardEvents(events);
        appLog('[SMS] BG: done, ${events.length} events logged');
    }
  }
}
