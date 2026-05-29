package dev.kkweon.sms_forwarder

import android.app.Notification
import android.app.Person
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap

/**
 * NotificationListenerService that watches incoming notifications from the
 * configured messaging app(s) and forwards their parsed contents to Dart
 * through an EventChannel.
 *
 * Owns the cached FlutterEngine so the same Dart isolate serves the UI
 * and incoming notification events — eliminates the separate background
 * entry point used by the old SmsReceiver pipeline.
 */
class MessageNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "SmsForwarder"
        const val ENGINE_ID = "sms_forwarder_listener_engine"
        const val EVENT_CHANNEL = "dev.kkweon.sms_forwarder/notifications"
        const val ALLOWED_PKG = "com.google.android.apps.messaging"
        const val OUR_PKG = "dev.kkweon.sms_forwarder"
        private const val DEDUP_TTL_MS = 5L * 60 * 1000
        private const val MAX_PENDING = 5

        @Volatile var sink: EventChannel.EventSink? = null

        /** Set briefly by the debug test helper so self-posted notifications pass the whitelist. */
        @Volatile var allowSelfPackage: Boolean = false

        private val seen = ConcurrentHashMap<String, Long>()
        private val pending = ArrayDeque<Map<String, Any?>>()
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "listener service onCreate")
        mainHandler.post { ensureEngine() }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "listener connected")
        // Ensure engine is up even if onCreate hadn't run yet (rare).
        mainHandler.post { ensureEngine() }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        val allowed = pkg == ALLOWED_PKG || (allowSelfPackage && pkg == OUR_PKG)
        if (!allowed) {
            diag("package_not_allowed", pkg, sbn.key)
            return
        }

        val extracted = extract(sbn.notification)
        if (extracted == null) {
            diag("no_extractable_body", pkg, sbn.key)
            return
        }
        val (sender, body) = extracted
        if (body.isBlank()) {
            diag("blank_body", pkg, sbn.key)
            return
        }

        val now = System.currentTimeMillis()
        // Prune stale entries opportunistically (cheap; ConcurrentHashMap-safe).
        val it = seen.entries.iterator()
        while (it.hasNext()) {
            if (now - it.next().value > DEDUP_TTL_MS) it.remove()
        }

        val dedupKey = "${sbn.key}:${body.hashCode()}"
        val last = seen[dedupKey]
        if (last != null && now - last < DEDUP_TTL_MS) {
            Log.d(TAG, "dedup hit for $dedupKey, skipping")
            return
        }
        seen[dedupKey] = now

        val payload = mapOf(
            "packageName" to pkg,
            "sender" to sender,
            "body" to body,
            "postTime" to sbn.postTime,
            "key" to sbn.key,
        )

        mainHandler.post { dispatch(payload) }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // no-op
    }

    /**
     * Surface a drop reason both to logcat and to the Dart Debug Log by
     * pushing a small map through the same EventChannel sink that carries
     * real events. The Dart dispatcher logs and skips entries that carry
     * a `diag` field instead of processing them.
     */
    private fun diag(reason: String, pkg: String?, sbnKey: String?) {
        Log.d(TAG, "dropped: $reason pkg=$pkg key=$sbnKey")
        val payload = mapOf<String, Any?>(
            "diag" to reason,
            "packageName" to pkg,
            "key" to sbnKey,
        )
        mainHandler.post { dispatch(payload) }
    }

    private fun dispatch(payload: Map<String, Any?>) {
        val s = sink
        if (s == null) {
            // Dart hasn't subscribed yet (cold start). Buffer with drop-oldest.
            if (pending.size >= MAX_PENDING) pending.removeFirst()
            pending.addLast(payload)
            Log.d(TAG, "sink null; buffered (size=${pending.size})")
            return
        }
        try {
            s.success(payload)
        } catch (e: Exception) {
            Log.e(TAG, "sink.success failed: ${e.message}", e)
        }
    }

    private fun ensureEngine() {
        val cache = FlutterEngineCache.getInstance()
        var engine = cache.get(ENGINE_ID)
        if (engine == null) {
            Log.d(TAG, "creating cached FlutterEngine")
            engine = FlutterEngine(applicationContext)
            // Register all Flutter plugins before executing the entrypoint
            // so that platform channels (e.g. another_telephony, shared_preferences,
            // permission_handler) are wired up when Dart starts.
            GeneratedPluginRegistrant.registerWith(engine)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            cache.put(ENGINE_ID, engine)
            // Wire shared channels (both telephony and notifications/control)
            // exactly once on engine creation, so they exist even when no
            // Activity has attached.
            MainActivity.registerChannels(engine, applicationContext)
            NotificationControlChannel.register(engine, applicationContext)
            SmsSenderChannel.register(engine, applicationContext)
            attachEventChannel(engine)
        } else {
            // Engine already exists; just (re-)attach the EventChannel sink
            // hook if it isn't there. setStreamHandler replaces any prior.
            attachEventChannel(engine)
        }
    }

    private fun attachEventChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    Log.d(TAG, "EventChannel onListen; draining ${pending.size} buffered")
                    sink = events
                    while (pending.isNotEmpty()) {
                        try {
                            events.success(pending.pollFirst())
                        } catch (e: Exception) {
                            Log.e(TAG, "drain failed: ${e.message}", e)
                            break
                        }
                    }
                }

                override fun onCancel(args: Any?) {
                    Log.d(TAG, "EventChannel onCancel")
                    sink = null
                }
            })
    }

    private fun extract(n: Notification): Pair<String, String>? {
        val extras = n.extras ?: return null

        // 1. MessagingStyle (preferred): EXTRA_MESSAGES is a Parcelable[]
        //    of Bundles. Newest message is the last element.
        val msgs = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        if (msgs != null && msgs.isNotEmpty()) {
            val last = msgs.last() as? Bundle
            if (last != null) {
                val text = last.getCharSequence("text")?.toString().orEmpty()
                if (text.isNotBlank()) {
                    val sender = last.getCharSequence("sender")?.toString()
                        ?: senderFromPerson(last)
                        ?: extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
                        ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                        ?: "unknown"
                    return sender to text
                }
            }
        }

        // 2. BigTextStyle / plain fallback.
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val chosen = big?.takeIf { it.isNotBlank() } ?: text?.takeIf { it.isNotBlank() }
        return chosen?.let { title to it }
    }

    @Suppress("DEPRECATION")
    private fun senderFromPerson(bundle: Bundle): String? {
        return try {
            val person = bundle.getParcelable<Person>("sender_person")
            person?.name?.toString()
        } catch (_: Throwable) {
            null
        }
    }
}
