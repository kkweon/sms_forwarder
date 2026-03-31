# SMS Forwarder

A personal Android app that automatically forwards SMS messages containing verification codes to one or more phone numbers.

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
| `another_telephony` | Receive and send SMS (background-capable) |
| `permission_handler` | Request SMS permissions at runtime |
| `shared_preferences` | Persist settings and log |

## Development

Install [Lefthook](https://github.com/evilmartians/lefthook), then:

```bash
flutter pub get
lefthook install
```

This installs git hooks that run `dart format`, `dart analyze`, and `flutter test` on every commit.

## Testing SMS forwarding with an emulator

Real-device SMS broadcast injection requires `BROADCAST_SMS` permission (system-only), so use an emulator instead — it exposes a telnet console that accepts `sms send`.

### One-time emulator setup

```bash
# Install emulator binary and a system image (x86_64 for speed)
~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager \
  "emulator" \
  "system-images;android-34;google_apis;x86_64"

# Create an AVD
~/Android/Sdk/cmdline-tools/latest/bin/avdmanager create avd \
  --name "test_avd" \
  --package "system-images;android-34;google_apis;x86_64" \
  --device "pixel_6"
```

### Start the emulator

```bash
~/Android/Sdk/emulator/emulator -avd test_avd -no-window -no-audio -gpu swiftshader_indirect &
adb wait-for-device
# Wait until fully booted
until [ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null)" = "1" ]; do sleep 3; done
```

### Install, configure, and test

```bash
# Build & install debug build
flutter build apk --debug
flutter install --debug -d emulator-5554

# Grant SMS permissions
for perm in RECEIVE_SMS READ_SMS SEND_SMS READ_PHONE_STATE READ_PHONE_NUMBERS; do
  adb -s emulator-5554 shell pm grant dev.kkweon.sms_forwarder android.permission.$perm
done

# Write settings (enable forwarding, set destination number)
python3 -c "
import base64
xml = '''<?xml version=\\'1.0\\' encoding=\\'utf-8\\' standalone=\\'yes\\' ?>
<map>
    <boolean name=\"flutter.forwarding_enabled\" value=\"true\" />
    <string name=\"flutter.destination_numbers\">VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu![\"+15550001234\"]</string>
</map>'''
print(base64.b64encode(xml.encode()).decode())
" | xargs -I{} adb -s emulator-5554 shell \
  "run-as dev.kkweon.sms_forwarder sh -c 'echo {} | base64 -d > /data/data/dev.kkweon.sms_forwarder/shared_prefs/FlutterSharedPreferences.xml'"

# Restart app so it reads the new settings
adb -s emulator-5554 shell am force-stop dev.kkweon.sms_forwarder
adb -s emulator-5554 shell am start -n dev.kkweon.sms_forwarder/.MainActivity
sleep 8
```

### Inject a test SMS

```python
import socket, os, time

s = socket.socket()
s.connect(('localhost', 5554))
s.recv(1024)  # banner

token = open(os.path.expanduser('~/.emulator_console_auth_token')).read().strip()
s.send(f'auth {token}\n'.encode()); time.sleep(0.5); s.recv(1024)

s.send(b'sms send +19999999999 "Your verification code is 123456"\n')
time.sleep(0.5); print(s.recv(1024).decode())
s.close()
```

### Verify in logcat

```bash
adb -s emulator-5554 logcat | grep -E "SmsForwarder|flutter.*SMS|flutter.*BG"
```

Expected output:

```
D SmsForwarder: SMS received from=+19999999999 bodyLen=34
D SmsForwarder: Starting background FlutterEngine
D SmsForwarder: Headless FlutterEngine started for backgroundSmsEntryPoint
I flutter  : [SMS] backgroundSmsEntryPoint: from=+19999999999 body="Your verification code is 123456"
I flutter  : [SMS] BG: forwarding to [+15550001234]
I flutter  : [SMS] send to +15550001234 status=SendStatus.SENT
I flutter  : [SMS] send to +15550001234 status=SendStatus.DELIVERED
```
