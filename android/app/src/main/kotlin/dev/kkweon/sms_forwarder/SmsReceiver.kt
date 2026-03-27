package dev.kkweon.sms_forwarder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Replaces another_telephony's IncomingSmsReceiver.
 *
 * Root-cause fix: another_telephony v0.4.1 calls the deprecated
 * SmsMessage.createFromPdu(byte[]) without a format string. On LTE networks
 * the SMS_RECEIVED intent carries a "format" extra ("3gpp"/"3gpp2") that must
 * be passed to createFromPdu(pdu, format); without it the method returns null
 * for some PDU encodings, causing message.body to be null in Dart.
 *
 * Telephony.Sms.Intents.getMessagesFromIntent() reads the format string from
 * intent extras and calls the correct overload, fixing the null-body bug.
 * This is the correct Android API (API 19+) for receiving SMS broadcasts.
 *
 * Foreground path: live EventChannel sink (SmsEventChannel.sink) set by
 *   MainActivity when the Flutter UI is active.
 * Background path: pending SMS data is written to SharedPreferences (with the
 *   "flutter." key prefix so Dart's shared_preferences package reads it), then
 *   a fresh headless FlutterEngine is started with the backgroundSmsEntryPoint
 *   Dart entry point, which reads and forwards the pending SMS.
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsForwarder"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // KEY FIX: getMessagesFromIntent reads the "format" extra and calls
        // createFromPdu(pdu, format), avoiding the null-body bug.
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            ?.takeIf { it.isNotEmpty() } ?: return

        val address = messages[0].originatingAddress ?: ""
        val body = messages.joinToString("") { it.messageBody ?: "" }
        Log.d(TAG, "SMS received from=$address bodyLen=${body.length}")
        if (body.isBlank()) {
            Log.d(TAG, "SMS body is blank, ignoring")
            return
        }

        val data = mapOf("address" to address, "body" to body)

        // Foreground path: deliver directly via the live EventChannel sink.
        // The sink is non-null only while the Flutter UI is in the foreground.
        SmsEventChannel.sink?.let { sink ->
            Log.d(TAG, "Delivering via foreground EventChannel sink")
            sink.success(data)
            return
        }

        // Background path: write to SharedPreferences then start a headless
        // FlutterEngine that runs backgroundSmsEntryPoint() in Dart.
        Log.d(TAG, "No foreground sink — starting background FlutterEngine")
        val pendingResult = goAsync() // extends the onReceive window to ~60s
        Thread {
            try {
                // Write with the "flutter." prefix so Dart's shared_preferences
                // package can read the values directly via SharedPreferences.getInstance().
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                )
                prefs.edit()
                    .putString("flutter.pending_bg_sms_address", address)
                    .putString("flutter.pending_bg_sms_body", body)
                    .apply()
                Log.d(TAG, "Wrote pending SMS to SharedPreferences")

                // FlutterEngine must be created on the main thread.
                Handler(Looper.getMainLooper()).post {
                    try {
                        val loader = FlutterInjector.instance().flutterLoader()
                        loader.startInitialization(context.applicationContext)
                        loader.ensureInitializationComplete(
                            context.applicationContext, null
                        )
                        val engine = FlutterEngine(context.applicationContext)
                        engine.dartExecutor.executeDartEntrypoint(
                            DartExecutor.DartEntrypoint(
                                loader.findAppBundlePath(),
                                "backgroundSmsEntryPoint"
                            )
                        )
                        Log.d(TAG, "Headless FlutterEngine started for backgroundSmsEntryPoint")
                        // Destroy the engine after 60 s to free resources.
                        Handler(Looper.getMainLooper()).postDelayed({
                            engine.destroy()
                            Log.d(TAG, "Headless FlutterEngine destroyed")
                        }, 60_000)
                        // The engine runs backgroundSmsEntryPoint asynchronously.
                        // pendingResult.finish() signals that BroadcastReceiver
                        // setup is done; the engine continues independently.
                    } finally {
                        pendingResult.finish()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error in background SMS handling: ${e.message}", e)
                pendingResult.finish()
            }
        }.start()
    }
}
