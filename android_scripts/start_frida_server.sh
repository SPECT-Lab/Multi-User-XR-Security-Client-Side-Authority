#!/bin/bash
# start_frida_server.sh — push a frida-server binary to a rooted device and run it.
# With no server argument it uses the bundled
#   gadget_injection/frida/frida-server-17.9.1-android-arm64
# Usage:   ./start_frida_server.sh <device-serial> [local-frida-server] [remote-path]
# Example: ./start_frida_server.sh 357de4330506   (uses the bundled server)

set -e

if [ -z "${1:-}" ]; then
  echo "Error: missing arguments"
  echo "Usage: $0 <device-serial> [local-frida-server] [remote-path]"
  echo "Example: $0 357de4330506   (uses the bundled gadget_injection/frida server)"
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

SERIAL=$1
LOCAL_SERVER=${2:-"$REPO_ROOT/gadget_injection/frida/frida-server-17.9.1-android-arm64"}
REMOTE_SERVER=${3:-"/data/local/tmp/frida-server"}

if [ ! -f "$LOCAL_SERVER" ]; then
  echo "Error: local frida-server not found: $LOCAL_SERVER"
  echo "Run setup.sh to decompress gadget_injection/frida/*.xz, or pass an explicit path."
  exit 1
fi

echo "Pushing $LOCAL_SERVER -> $SERIAL:$REMOTE_SERVER"
adb -s "$SERIAL" push "$LOCAL_SERVER" "$REMOTE_SERVER" >/dev/null \
  || { echo "Error: adb push failed"; exit 1; }

adb -s "$SERIAL" shell su -c "chmod 755 $REMOTE_SERVER" \
  || { echo "Error: chmod on device failed — is it rooted?"; exit 1; }

if ! adb -s "$SERIAL" shell su -c "setenforce 0"; then
  echo "Error: failed to setenforce 0 — is device rooted?"
  exit 1
fi

adb -s "$SERIAL" shell su -c "pkill -f frida-server" 2>/dev/null || true
sleep 1

echo "Starting frida-server"
adb -s "$SERIAL" shell su -c "nohup $REMOTE_SERVER >/dev/null 2>&1 &"
sleep 2

FRIDA_PID=$(adb -s "$SERIAL" shell pidof frida-server 2>/dev/null | tr -d '\r')
if [ -z "$FRIDA_PID" ]; then
  echo "Error: frida-server failed to start"
  exit 1
fi
echo "frida-server running on $SERIAL (pid: $FRIDA_PID, path: $REMOTE_SERVER)"
