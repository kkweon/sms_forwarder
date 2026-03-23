# SMS Forwarder

A personal Android app that automatically forwards SMS messages containing verification codes to one or more phone numbers.

## Setup

### 1. Build & install APK

```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
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
