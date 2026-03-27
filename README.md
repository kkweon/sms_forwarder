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
