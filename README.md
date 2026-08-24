# SMS Forwarder

A personal Android app that automatically forwards verification-code messages (both SMS and RCS) to one or more phone numbers.

## How it works

The app ingests messages from **two** sources that feed the same Flutter pipeline:

1. **`SmsReceiver`** — a `RECEIVE_SMS` BroadcastReceiver that reads incoming SMS straight from the telephony layer (the raw PDU). Because it never goes through the notification system, it is **not** subject to Android 15+'s OTP notification redaction. This is the reliable path for SMS verification codes.
2. **`MessageNotificationListener`** — a `NotificationListenerService` watching Google Messages (`com.google.android.apps.messaging`). This covers **RCS** messages, which never fire `SMS_RECEIVED`.

Both sources push a parsed (sender, body) into one cached `FlutterEngine` via an `EventChannel`. Each event is filtered against a keyword + digit pattern and forwarded to the configured destination numbers as an outgoing SMS.

Because an incoming SMS fires *both* sources a few seconds apart, a **dedup layer** guarantees the same message body is forwarded to the same destination at most once within a 5-minute TTL:

- `ForwardDedupCache` (SharedPreferences, keyed by `bodyHash|destination`) survives process restarts and is recorded **on successful send only** — a failed/timeout send is left open so the other source can retry.
- `ForwardReservation` (in-memory, synchronous) closes the race between two near-simultaneous events on the same isolate.

Every attempt (sent/failed/timeout) is recorded in the in-app Forwarding Log regardless of dedup.

## Requirements

- Google Messages must be the device's messaging app (notifications are app-specific).
- Notification access must be granted to this app — the first launch shows a one-time dialog with a CTA to open Settings.
- `SEND_SMS` permission to deliver the forwarded message.
- `RECEIVE_SMS` + `SEND_SMS` (the SMS permission group) must be granted at runtime — the app requests them on launch alongside the phone permission.
- The `RECEIVE_SENSITIVE_NOTIFICATIONS` appop (see step 3) is now **optional**. The `SmsReceiver` reads SMS un-redacted, so it is no longer needed for SMS verification codes. It only matters for the notification/**RCS** path, where Android 15+ otherwise redacts OTP bodies to `"Sensitive notification content hidden"`. It cannot be declared in the manifest (protection level `signature|preinstalled|role|knownSigner`) and resets on every reinstall/update.

## Setup

### 1. Build & install APK

Common commands run through [Task](https://taskfile.dev) — `task` lists them all.

Build split APKs (smaller per-ABI binaries), version-stamped with the current datetime:

```bash
task build
```

Outputs:
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (~14.6MB)
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`   (~17.2MB)
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`      (~18.6MB)

The build's `versionName` is the datetime (e.g. `2026.05.28.2137`) and `versionCode` is
the Unix epoch seconds — always increasing and within Android's `versionCode` limit.

Install the APK matching your device's ABI (`arm64-v8a` by default; check `flutter devices`):

```bash
task install DEVICE=<YOUR-DEVICE-ID>                 # arm64-v8a
task install DEVICE=<YOUR-DEVICE-ID> ABI=armeabi-v7a # or x86_64
```

### 2. First launch

- Grant SMS permissions when prompted
- Add one or more destination phone numbers
- Toggle forwarding on

### 3. (Optional) Grant sensitive-notification access for the RCS path

SMS verification codes are handled by the `SmsReceiver` and need no special
setup. This step only improves the **RCS / notification** path: Android 15+
redacts OTP notification bodies for ordinary notification listeners, so an OTP
sent over RCS would be unreadable without it. Re-run after each `flutter install`:

```bash
scripts/setup-device.sh <YOUR-DEVICE-ID>   # device-id optional if only one is attached
```

This grants the `RECEIVE_SENSITIVE_NOTIFICATIONS` appop. The grant survives
reboots but **not** reinstalls/updates, so run it as the last step of every
deploy. To verify manually:

```bash
adb shell cmd appops get dev.kkweon.sms_forwarder RECEIVE_SENSITIVE_NOTIFICATIONS
# expect: RECEIVE_SENSITIVE_NOTIFICATIONS: allow
```

If a real OTP shows up in the logs as `body=Sensitive notification content hidden`,
this grant is missing.

## Dependencies

| Package | Purpose |
|---------|---------|
| `another_telephony` | Send outgoing SMS (`Telephony.sendSms`) |
| `permission_handler` | Request phone permissions for own-number detection |
| `shared_preferences` | Persist settings and forward history |
| `path_provider` | Locate the debug-log file location |

## Development

Install [Lefthook](https://github.com/evilmartians/lefthook), then run one-time setup:

```bash
task setup   # flutter pub get + lefthook install
```

This installs git hooks that run `dart format`, `dart analyze`, and `flutter test` on every commit.

Day-to-day:

```bash
task fix     # auto-fix lints + format (run before committing so the hook passes)
task test    # flutter test
```

## App icon

The launcher icon is a single vector master at
[`assets/logo/sms_forwarder_logo.svg`](assets/logo/sms_forwarder_logo.svg) — a
black outline envelope whose forward arrow pierces its right edge, on white.

Two things are derived from it, and neither should be edited by hand:

- **Adaptive icon (API 26+)** — `res/drawable/ic_launcher_foreground.xml` holds
  the same paths as an Android vector drawable, scaled to 0.78 so the mark stays
  inside the 66dp safe zone. It also serves as the `<monochrome>` layer, so
  Android 13+ themed icons work. The background is a flat white colour resource.
- **Legacy PNG mipmaps** — square and round, five densities, rendered from the
  SVG:

```bash
pip install cairosvg
task icons   # or: python3 scripts/render_icons.py
```

If you change the geometry in the SVG, mirror it into the vector drawable's
`pathData` and re-run the render script.

## Smoke-testing on a real device

Because intake is now notification-based, the easiest end-to-end test is the in-app **"Post test notification"** button (the test-tube icon in the AppBar). It posts a real `MessagingStyle` notification carrying `"Your verification code is 451287"` from our own package; the listener bypasses its Google-Messages whitelist for this single post and the rest of the pipeline runs unchanged.

```bash
task build MODE=debug
flutter install -d <device-id>
# Grant notification access:
adb shell am start -a android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS
# (toggle SMS Forwarder on, return to the app)
adb logcat -c
adb logcat -s SmsForwarder:V flutter:V &
# In the app, tap the test-tube icon. Expected:
#   SmsForwarder  listener connected
#   flutter       [NL] event from=Vanguard pkg=dev.kkweon.sms_forwarder body=Your verification code is 451287
#   flutter       [SMS] BG: forwarding to [<your-destination>]
#   flutter       [SMS] send to <dest> status=SendStatus.SENT
```

For end-to-end SMS / RCS verification, text the device a verification code from another phone and confirm a new entry appears in the in-app "Forwarding Log".
