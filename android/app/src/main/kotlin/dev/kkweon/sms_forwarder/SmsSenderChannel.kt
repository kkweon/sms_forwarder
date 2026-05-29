package dev.kkweon.sms_forwarder

import android.content.Context
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel that lets Dart send SMS via Android's [SmsManager] regardless
 * of whether [MainActivity] is currently attached. The previous path went
 * through `another_telephony`'s `plugins.shounakmulay.com/foreground_sms_channel`,
 * which is registered via the plugin's `ActivityAware` lifecycle and torn
 * down as soon as the Activity is destroyed — leaving the listener service's
 * cached engine without a handler and surfacing `MissingPluginException` at
 * forward time.
 */
object SmsSenderChannel {
    private const val TAG = "SmsForwarder"
    private const val CHANNEL = "dev.kkweon.sms_forwarder/sms"

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendMultipartSms" -> {
                        val to = call.argument<String>("to")
                        val message = call.argument<String>("message")
                        if (to.isNullOrBlank() || message == null) {
                            result.error("ARGS", "missing to/message", null)
                            return@setMethodCallHandler
                        }
                        result.success(send(context, to, message))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun send(context: Context, to: String, message: String): String {
        Log.d(TAG, "sendMultipartSms: to=$to len=${message.length}")
        return try {
            val mgr = smsManager(context)
            val parts = mgr.divideMessage(message)
            mgr.sendMultipartTextMessage(to, null, parts, null, null)
            Log.d(TAG, "sendMultipartSms: handed ${parts.size} part(s) to SmsManager")
            "sent"
        } catch (e: Exception) {
            Log.e(TAG, "sendMultipartTextMessage failed: ${e.message}", e)
            "failed"
        }
    }

    private fun smsManager(context: Context): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }
}
