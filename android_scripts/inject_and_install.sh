#!/bin/bash
# inject_and_install.sh — non-rooted device flow in one shot:
#   1) pull the installed app's APK split set off the device
#   2) inject the bundled Frida gadget into the entry library and re-sign
#   3) uninstall the stock build and install the patched build
#
# Input is the device serial and the app PACKAGE NAME (e.g. com.ivre.engage).
# Usage:   ./inject_and_install.sh <device-serial> <package-name> [device-type]
#   device-type: phone | quest   (default: phone; selects the PairIP-bypass variant)
# Example: ./inject_and_install.sh 357de4330506 com.ivre.engage quest

set -euo pipefail
shopt -s nullglob

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "Error: missing arguments"
  echo "Usage: $0 <device-serial> <package-name> [device-type: phone|quest]"
  echo "Example: $0 357de4330506 com.ivre.engage quest"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
GADGET="$REPO_ROOT/gadget_injection/frida/frida-gadget-17.9.1-android-arm64.so"
INJECT="$REPO_ROOT/gadget_injection/inject_frida_gadget.py"

SERIAL=$1
PACKAGE=$2
DEVICE_TYPE=${3:-phone}

WORK="apks/$PACKAGE"
PULLED="$WORK/pulled"
PATCHED="$WORK/patched"

if [ ! -f "$GADGET" ]; then
  echo "Error: bundled gadget not found: $GADGET"
  echo "Run setup.sh to decompress gadget_injection/frida/*.xz, or unxz it manually."
  exit 1
fi

echo "== 1/3  pull APK(s) for $PACKAGE =="
"$SCRIPT_DIR/pull_apk.sh" "$SERIAL" "$PACKAGE" "$PULLED"

PULLED_APKS=("$PULLED"/*.apk)
if [ ${#PULLED_APKS[@]} -eq 0 ]; then
  echo "Error: no APKs pulled into $PULLED"
  exit 1
fi

echo "== 2/3  inject Frida gadget ($DEVICE_TYPE) =="
python3 "$INJECT" --apks "${PULLED_APKS[@]}" --gadget "$GADGET" \
  --output "$PATCHED" --device-type "$DEVICE_TYPE"

echo "== 3/3  re-install patched build =="
SIGNED=("$PATCHED"/*_signed.apk)
if [ ${#SIGNED[@]} -eq 0 ]; then
  echo "Error: no *_signed.apk produced in $PATCHED"
  exit 1
fi
"$SCRIPT_DIR/adb_reinstall.sh" "$SERIAL" "$PACKAGE" "${SIGNED[@]}"

echo
echo "Done. Launch the app on the device, then run an attack hook:"
echo "  $SCRIPT_DIR/hook_gadget.sh $SERIAL $PACKAGE attack_hooks/example_attack_hooks/<hook>.js"
