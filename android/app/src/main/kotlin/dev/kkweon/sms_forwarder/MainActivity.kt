package dev.kkweon.sms_forwarder

import android.annotation.SuppressLint
import android.content.Context
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "SmsForwarder"
        private const val TELEPHONY_CHANNEL = "dev.kkweon.sms_forwarder/telephony"

        /**
         * Register the always-on MethodChannels on [engine]. Called from
         * [MessageNotificationListener.ensureEngine] so the channels are
         * wired up even when no Activity has attached yet.
         */
        fun registerChannels(engine: FlutterEngine, context: Context) {
            Log.d(TAG, "registerChannels: telephony")
            MethodChannel(engine.dartExecutor.binaryMessenger, TELEPHONY_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "getOwnPhoneNumbers" ->
                            result.success(getOwnPhoneNumbers(context))
                        else -> result.notImplemented()
                    }
                }
        }

        @SuppressLint("HardwareIds", "MissingPermission")
        private fun getOwnPhoneNumbers(context: Context): List<String> {
            return try {
                val tm = context.getSystemService(Context.TELEPHONY_SERVICE)
                    as TelephonyManager
                val numbers = listOfNotNull(
                    tm.line1Number?.takeIf { it.isNotBlank() },
                )
                Log.d(TAG, "getOwnPhoneNumbers: $numbers")
                numbers
            } catch (e: Exception) {
                Log.e(TAG, "getOwnPhoneNumbers failed: ${e.message}", e)
                emptyList()
            }
        }
    }

    /**
     * Attach to the FlutterEngine owned by [MessageNotificationListener] so
     * the UI shares its isolate (and therefore its in-memory state) with the
     * notification dispatcher. Falls back to a fresh engine in the rare race
     * where the Activity launches before the listener service has run.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cached = FlutterEngineCache.getInstance()
            .get(MessageNotificationListener.ENGINE_ID)
        if (cached != null) {
            Log.d(TAG, "provideFlutterEngine: using cached engine")
            return cached
        }
        Log.w(TAG, "provideFlutterEngine: cache miss; falling back to default")
        return super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // If we hit the cache-miss fallback above, the new engine needs the
        // shared channels wired up too.
        registerChannels(flutterEngine, applicationContext)
        NotificationControlChannel.register(flutterEngine, applicationContext)
        SmsSenderChannel.register(flutterEngine, applicationContext)
    }
}
