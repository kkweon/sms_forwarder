package dev.kkweon.sms_forwarder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log

/**
 * Manifest-registered BroadcastReceiver for SMS_RECEIVED.
 *
 * Reads the raw SMS straight from the telephony layer (the PDU in the
 * broadcast intent), so — unlike the notification listener — it is NOT
 * subject to Android 15+'s OTP notification redaction. It feeds the parsed
 * (sender, body) into the SAME cached-engine EventChannel pipeline the
 * notification listener uses, via [MessageNotificationListener.ingestExternal].
 *
 * Deliberately lightweight: no headless FlutterEngine / SharedPreferences /
 * backgroundSmsEntryPoint hand-off (the old pipeline). Cross-source
 * deduplication (this SMS vs. the parallel Google Messages notification) is
 * handled on the Dart side, keyed by message body + destination.
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsForwarder"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // getMessagesFromIntent reads the "format" extra and calls the correct
        // SmsMessage.createFromPdu overload — fixes the LTE null-body bug seen
        // with the deprecated single-arg overload — and joins multipart PDUs.
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            ?.takeIf { it.isNotEmpty() } ?: return

        val address = messages[0].originatingAddress ?: "unknown"
        val body = messages.joinToString("") { it.messageBody ?: "" }
        Log.d(TAG, "SMS received from=$address bodyLen=${body.length}")
        if (body.isBlank()) {
            Log.d(TAG, "SMS body is blank, ignoring")
            return
        }

        // Extend the onReceive window so the cached engine can boot on a cold
        // start before the process is reaped. ingestExternal runs synchronously
        // on the main thread (ensures engine, dedups, dispatches/buffers), so we
        // can finish() as soon as it returns.
        val pendingResult = goAsync()
        Handler(Looper.getMainLooper()).post {
            try {
                MessageNotificationListener.ingestExternal(
                    context, address, body, "sms_receiver"
                )
            } catch (e: Exception) {
                Log.e(TAG, "ingestExternal failed: ${e.message}", e)
            } finally {
                pendingResult.finish()
            }
        }
    }
}
