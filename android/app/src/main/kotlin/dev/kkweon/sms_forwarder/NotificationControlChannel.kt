package dev.kkweon.sms_forwarder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel for managing notification-listener access and posting a
 * synthetic test notification (available in all builds — useful for
 * verifying the pipeline without sending a real SMS).
 */
object NotificationControlChannel {
    private const val TAG = "SmsForwarder"
    private const val CHANNEL = "dev.kkweon.sms_forwarder/notifications/control"
    private const val TEST_CHANNEL_ID = "sms_forwarder_test_notifications"
    private const val TEST_NOTIFICATION_ID = 4242

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessGranted" -> result.success(isAccessGranted(context))
                    "openSettings" -> {
                        openSettings(context)
                        result.success(null)
                    }
                    "postTestNotification" -> {
                        postTestNotification(context)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAccessGranted(context: Context): Boolean {
        val enabled = NotificationManagerCompat.getEnabledListenerPackages(context)
        val ok = enabled.contains(context.packageName)
        Log.d(TAG, "isAccessGranted=$ok (enabled=$enabled)")
        return ok
    }

    private fun openSettings(context: Context) {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun postTestNotification(context: Context) {
        Log.d(TAG, "postTestNotification: posting synthetic MessagingStyle notification")
        ensureTestChannel(context)
        @Suppress("DEPRECATION")
        val style = NotificationCompat.MessagingStyle("Self")
            .addMessage(
                "Your verification code is 451287",
                System.currentTimeMillis(),
                "Vanguard" as CharSequence?,
            )

        val n = NotificationCompat.Builder(context, TEST_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setStyle(style)
            .setAutoCancel(true)
            .build()

        // Temporarily let the listener accept notifications from our own
        // package so the synthetic one isn't filtered by the whitelist.
        MessageNotificationListener.allowSelfPackage = true
        try {
            NotificationManagerCompat.from(context)
                .notify(TEST_NOTIFICATION_ID, n)
        } catch (e: SecurityException) {
            Log.e(TAG, "postTestNotification: missing POST_NOTIFICATIONS?: ${e.message}", e)
        }
        // Re-disable the bypass shortly after; the listener will have
        // already processed the post by then.
        Handler(Looper.getMainLooper()).postDelayed({
            MessageNotificationListener.allowSelfPackage = false
        }, 1500)
    }

    private fun ensureTestChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(TEST_CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            TEST_CHANNEL_ID,
            "SMS Forwarder test notifications",
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        mgr.createNotificationChannel(ch)
    }
}
