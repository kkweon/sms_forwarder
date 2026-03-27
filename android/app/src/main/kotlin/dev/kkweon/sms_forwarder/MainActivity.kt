package dev.kkweon.sms_forwarder

import android.annotation.SuppressLint
import android.content.Context
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "dev.kkweon.sms_forwarder/telephony"

    companion object {
        private const val TAG = "SmsForwarder"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine: registering MethodChannel")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getOwnPhoneNumbers" -> result.success(getOwnPhoneNumbers())
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("HardwareIds", "MissingPermission")
    private fun getOwnPhoneNumbers(): List<String> {
        return try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val numbers = listOfNotNull(tm.line1Number?.takeIf { it.isNotBlank() })
            Log.d(TAG, "getOwnPhoneNumbers: $numbers")
            numbers
        } catch (e: Exception) {
            Log.e(TAG, "getOwnPhoneNumbers failed: ${e.message}", e)
            emptyList()
        }
    }
}
