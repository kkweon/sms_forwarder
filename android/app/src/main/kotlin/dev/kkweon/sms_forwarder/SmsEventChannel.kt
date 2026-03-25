package dev.kkweon.sms_forwarder

import io.flutter.plugin.common.EventChannel

/** Singleton holding the live [EventChannel.EventSink] set by [MainActivity].
 *  Non-null only while the Flutter UI is active (foreground). */
object SmsEventChannel {
    @Volatile
    var sink: EventChannel.EventSink? = null
}
