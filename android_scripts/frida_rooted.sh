#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: missing arguments"
  echo "Usage: $0 <device-serial> <frida-server-path-on-device> <package-name>"
  echo "Example: $0 357de4330506 /data/local/tmp/frida-server com.ivre.engage"
  exit 1
fi

SERIAL=$1
FRIDA_SERVER=$2
PACKAGE=$3

adb -s "$SERIAL" shell su -c "setenforce 0"
if [ $? -ne 0 ]; then
  echo "Error: failed to set setenforce 0 — is device rooted?"
  exit 1
fi

adb -s "$SERIAL" shell su -c "pkill -f frida-server" 2>/dev/null
sleep 1

echo "Starting frida-server"
adb -s "$SERIAL" shell su -c "$FRIDA_SERVER >/dev/null 2>&1 &"
sleep 2

FRIDA_PID=$(adb -s "$SERIAL" shell pidof frida-server 2>/dev/null | tr -d '\r')
if [ -z "$FRIDA_PID" ]; then
  echo "Error: frida-server failed to start"
  exit 1
fi
echo "frida-server running (pid: $FRIDA_PID)"

PID=$(adb -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')

if [ -z "$PID" ]; then

  echo "App not running — launching $PACKAGE..."
  adb -s "$SERIAL" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 3

  PID=$(adb -s "$SERIAL" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')
  if [ -z "$PID" ]; then
    echo "Error: failed to launch $PACKAGE"
    exit 1
  fi

fi

echo "$PACKAGE running (pid: $PID)"

adb -s "$SERIAL" forward tcp:27042 tcp:27042

frida -H 127.0.0.1:27042 -p "$PID" -e "console.log('frida attach ok')" 2>&1
