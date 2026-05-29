package dev.kkweon.sms_forwarder

import android.app.Notification
import android.app.Person
import android.content.Context
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
 *
 * The engine + dispatch plumbing lives in the [companion object] (static) so
 * [SmsReceiver] can feed raw SMS into the *same* pipeline via [ingestExternal]
 * without depending on the service instance being alive.
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

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * Feed a message from a non-notification source (e.g. [SmsReceiver]'s
         * raw SMS) into the same pipeline the notification listener uses.
         *
         * MUST be called on the main thread (the engine + dispatch plumbing is
         * main-thread-only). Runs synchronously: ensures the cached engine
         * exists, applies dedup, and dispatches/buffers the payload — so a
         * caller using `goAsync()` can safely `finish()` immediately after.
         *
         * Kotlin intake dedup here is per-source (the key includes
         * [packageName]); cross-source dedup between SMS and the Messages
         * notification is handled on the Dart side, keyed by body + destination.
         */
        fun ingestExternal(context: Context, sender: String, body: String, packageName: String) {
            ensureEngine(context)
            if (body.isBlank()) {
                Log.d(TAG, "ingestExternal: blank body from $packageName, ignoring")
                return
            }
            val dedupKey = "$packageName:${body.hashCode()}"
            if (!passesDedup(dedupKey)) return
            val payload = mapOf<String, Any?>(
                "packageName" to packageName,
                "sender" to sender,
                "body" to body,
                "postTime" to System.currentTimeMillis(),
                "key" to dedupKey,
            )
            dispatch(payload)
        }

        /**
         * Opportunistically prune stale entries, then check-and-record
         * [dedupKey]. Returns false (skip) on a fresh hit within the TTL.
         */
        private fun passesDedup(dedupKey: String): Boolean {
            val now = System.currentTimeMillis()
            val it = seen.entries.iterator()
            while (it.hasNext()) {
                if (now - it.next().value > DEDUP_TTL_MS) it.remove()
            }
            val last = seen[dedupKey]
            if (last != null && now - last < DEDUP_TTL_MS) {
                Log.d(TAG, "dedup hit for $dedupKey, skipping")
                return false
            }
            seen[dedupKey] = now
            return true
        }

        fun ensureEngine(context: Context) {
            val appContext = context.applicationContext
            val cache = FlutterEngineCache.getInstance()
            val engine = cache.get(ENGINE_ID)
            if (engine == null) {
                Log.d(TAG, "creating cached FlutterEngine")
                val newEngine = FlutterEngine(appContext)
                // Register all Flutter plugins before executing the entrypoint
                // so that platform channels (e.g. shared_preferences,
                // permission_handler) are wired up when Dart starts.
                GeneratedPluginRegistrant.registerWith(newEngine)
                newEngine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault()
                )
                cache.put(ENGINE_ID, newEngine)
                // Wire shared channels exactly once on engine creation, so they
                // exist even when no Activity has attached.
                MainActivity.registerChannels(newEngine, appContext)
                NotificationControlChannel.register(newEngine, appContext)
                SmsSenderChannel.register(newEngine, appContext)
                attachEventChannel(newEngine)
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
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "listener service onCreate")
        mainHandler.post { ensureEngine(applicationContext) }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "listener connected")
        // Ensure engine is up even if onCreate hadn't run yet (rare).
        mainHandler.post { ensureEngine(applicationContext) }
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

        val dedupKey = "${sbn.key}:${body.hashCode()}"
        if (!passesDedup(dedupKey)) return

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
