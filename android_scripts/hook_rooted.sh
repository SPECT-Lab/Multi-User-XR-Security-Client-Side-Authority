#!/bin/bash
# hook_rooted.sh — run an attack hook on a ROOTED device via frida-server.
# Loads the bundled runtime logger (provides the Il2Cpp global) then your hook,
# attaching to the app by PID. frida-server must already be running on the device
# (see start_frida_server.sh).
#
# Input is the device serial and the app PACKAGE NAME.
# Usage:   ./hook_rooted.sh <device-serial> <package-name> <frida-script-path>
# Example: ./hook_rooted.sh 357de4330506 com.ivre.engage attack_hooks/example_attack_hooks/video_surveillance.js

set -euo pipefail

if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
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
  echo "Error: hook script not found: $SCRIPT"
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

SCRIPT_NAME=$(basename "$SCRIPT" .js)
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/${SERIAL}_${PACKAGE}_${SCRIPT_NAME}.txt"
mkdir -p "$LOG_DIR"

# frida-server listens on 127.0.0.1:27042 inside the device — forward it out.
adb -s "$SERIAL" forward tcp:27042 tcp:27042

echo "Device:  $SERIAL"
echo "Package: $PACKAGE"
echo "PID:     $PID"
echo "Script:  $SCRIPT"
echo "Log:     $LOG_FILE"
echo "Attaching via frida-server..."

# Attach to the app by PID over the forwarded frida-server port. The runtime
# logger bundles frida-il2cpp-bridge and exposes the Il2Cpp global the hook needs.
frida -H 127.0.0.1:27042 -p "$PID" \
  -l "$LOGGER" \
  -l "$SCRIPT" 2>&1 | tee "$LOG_FILE"
