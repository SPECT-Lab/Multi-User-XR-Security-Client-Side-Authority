#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: missing arguments"
  echo "Usage: $0 <device-serial> <package-name> <output-directory>"
  echo "Example: $0 357de4330506 com.ivre.engage 'APK/'"
  exit 1
fi

SERIAL=$1
PACKAGE=$2
OUT_DIR=${3:-"apks/${PACKAGE}"}

PATHS=$(adb -s "$SERIAL" shell pm path "$PACKAGE" 2>/dev/null | tr -d '\r')

if [ -z "$PATHS" ]; then
  echo "Error: package '$PACKAGE' not found on device $SERIAL"
  exit 1
fi

echo "$PATHS"

mkdir -p "$OUT_DIR"

while IFS= read -r line; do
  APK_PATH=$(echo "$line" | sed 's/package://')
  APK_NAME=$(basename "$APK_PATH")
  DEST="$OUT_DIR/$APK_NAME"

  echo "Pulling $APK_PATH -> $DEST"
  adb -s "$SERIAL" pull "$APK_PATH" "$DEST"

done <<< "$PATHS"

ls -lh "$OUT_DIR/"