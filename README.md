# SMS Forwarder

A personal Android app that automatically forwards verification-code messages (both SMS and RCS) to one or more phone numbers.

## How it works

The app watches notifications posted by Google Messages (`com.google.android.apps.messaging`) via a `NotificationListenerService`. Each incoming notification is parsed for a sender and body, filtered against a keyword + digit pattern, and forwarded to the configured destination numbers as an outgoing SMS. Because notifications cover both SMS and RCS, the app catches verification codes regardless of which protocol the sender uses.

## Requirements

- Google Messages must be the device's messaging app (notifications are app-specific).
- Notification access must be granted to this app — the first launch shows a one-time dialog with a CTA to open Settings.
- `SEND_SMS` permission to deliver the forwarded message.

## Setup

### 1. Build & install APK

Build split APKs (smaller per-ABI binaries):

```bash
flutter build apk --split-per-abi --release
```

Outputs:
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (~14.6MB)
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`   (~17.2MB)
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`      (~18.6MB)

Install the APK matching your device's ABI (check `flutter devices` for the architecture):

```bash
flutter install \
  --device-id <YOUR-DEVICE-ID> \
  --use-application-binary=build/app/outputs/flutter-apk/app-<ABI>-release.apk
```

Example for Pixel 7 Pro (arm64):

```bash
flutter install \
  --device-id 2B141FDH300F4B \
  --use-application-binary=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### 2. First launch

- Grant SMS permissions when prompted
- Add one or more destination phone numbers
- Toggle forwarding on

## Dependencies

| Package | Purpose |
|---------|---------|
| `another_telephony` | Send outgoing SMS (`Telephony.sendSms`) |
| `permission_handler` | Request phone permissions for own-number detection |
| `shared_preferences` | Persist settings and forward history |
| `path_provider` | Locate the debug-log file location |

## Development

Install [Lefthook](https://github.com/evilmartians/lefthook), then:

```bash
flutter pub get
lefthook install
```

This installs git hooks that run `dart format`, `dart analyze`, and `flutter test` on every commit.

## Smoke-testing on a real device

Because intake is now notification-based, the easiest end-to-end test is the in-app **"Post test notification"** button (the test-tube icon in the AppBar). It posts a real `MessagingStyle` notification carrying `"Your verification code is 451287"` from our own package; the listener bypasses its Google-Messages whitelist for this single post and the rest of the pipeline runs unchanged.

```bash
flutter build apk --debug
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
