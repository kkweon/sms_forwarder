#!/usr/bin/env bash
#
# Grants the device-side permissions that the app cannot grant itself.
#
# RECEIVE_SENSITIVE_NOTIFICATIONS is protectionLevel
# signature|preinstalled|role|knownSigner, so a sideloaded build can never
# obtain it through the manifest. Without it, Android 15+ redacts OTP/2FA
# notification bodies to the literal string "Sensitive notification content
# hidden" before the listener sees them — which silently breaks forwarding of
# exactly the messages we care about. The appop below is the only practical
# override, and it RESETS on every reinstall/update, so re-run after each
# `flutter install`.
#
# Usage:
#   scripts/setup-device.sh [device-id]
# If device-id is omitted, the single attached device is used.

set -euo pipefail

PKG="dev.kkweon.sms_forwarder"
DEVICE="${1:-}"
ADB=(adb)
[[ -n "$DEVICE" ]] && ADB=(adb -s "$DEVICE")

echo "Granting RECEIVE_SENSITIVE_NOTIFICATIONS to $PKG ..."
"${ADB[@]}" shell appops set "$PKG" RECEIVE_SENSITIVE_NOTIFICATIONS allow

STATE="$("${ADB[@]}" shell cmd appops get "$PKG" RECEIVE_SENSITIVE_NOTIFICATIONS)"
echo "  -> $STATE"

case "$STATE" in
  *allow*) echo "OK: un-redacted notification content is now visible to the listener." ;;
  *)       echo "WARNING: appop is not 'allow' — OTP bodies will stay redacted." >&2; exit 1 ;;
esac
