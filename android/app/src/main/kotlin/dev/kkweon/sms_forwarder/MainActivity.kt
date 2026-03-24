package dev.kkweon.sms_forwarder

import android.annotation.SuppressLint
import android.content.Context
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "dev.kkweon.sms_forwarder/telephony"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
            listOfNotNull(tm.line1Number?.takeIf { it.isNotBlank() })
        } catch (e: Exception) {
            emptyList()
        }
    }
}
