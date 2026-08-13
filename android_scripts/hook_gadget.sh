#!/bin/bash
# hook_gadget.sh — run an attack hook on a NON-ROOTED device via the injected
# Frida gadget. Loads the bundled runtime logger (provides the Il2Cpp global)
# then your hook. The app must already be patched (see inject_and_install.sh)
# and running.
#
# Input is the device serial and the app PACKAGE NAME.
# Usage:   ./hook_gadget.sh <device-serial> <package-name> <frida-script-path>
# Example: ./hook_gadget.sh 357de4330506 com.ivre.engage attack_hooks/example_attack_hooks/video_surveillance.js

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: missing arguments"
  echo "Usage: $0 <device-serial> <package-name> <frida-script-path>"
  echo "Example: $0 357de4330506 com.ivre.engage attack_hooks/example_attack_hooks/video_surveillance.js"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOGGER="$REPO_ROOT/runtime_logging/runtime_logger.js"

SERIAL=$1
PACKAGE=$2
SCRIPT=$3

if [ ! -f "$SCRIPT" ]; then
  echo "Error: script not found: $SCRIPT"
  exit 1
fi
if [ ! -f "$LOGGER" ]; then
  echo "Error: runtime logger not found: $LOGGER (run setup.sh)"
  exit 1
fi

PID=$(adb -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')

if [ -z "$PID" ]; then
  echo "Error: '$PACKAGE' is not running on device $SERIAL"
  echo "Launch the app first, then re-run this script"
  exit 1
fi

# build log filename from args
SCRIPT_NAME=$(basename "$SCRIPT" .js)
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/${SERIAL}_${PACKAGE}_${SCRIPT_NAME}.txt"

mkdir -p "$LOG_DIR"

# Forward the gadget's listen port from device to localhost.
# The gadget listens on 127.0.0.1:27042 inside the device — adb forward
# makes that port reachable as localhost:27042 on this machine.
adb -s "$SERIAL" forward tcp:27042 tcp:27042

echo "Device:  $SERIAL"
echo "Package: $PACKAGE"
echo "PID:     $PID"
echo "Script:  $SCRIPT"
echo "Log:     $LOG_FILE"
echo "Attaching..."

# Connect to the gadget over the forwarded port (-H 127.0.0.1:27042).
# The gadget registers itself as "Gadget" — use that instead of -p <pid>.
# The runtime logger bundles frida-il2cpp-bridge and exposes the Il2Cpp global.
# This works on non-rooted devices; frida-server on device is not required.
frida -H 127.0.0.1:27042 \
  -n Gadget \
  -l "$LOGGER" \
  -l "$SCRIPT" 2>&1 | tee "$LOG_FILE"
