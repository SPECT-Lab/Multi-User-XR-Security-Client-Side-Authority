#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: missing arguments"
  echo "Usage: $0 <device-serial> <package-name> <apk-or-apks...>"
  exit 1
fi  

SERIAL=$1
PACKAGE=$2
shift 2
APKS=("$@")

adb -s "$SERIAL" shell pm uninstall "$PACKAGE"
adb -s "$SERIAL" install-multiple "${APKS[@]}"
