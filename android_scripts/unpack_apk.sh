#!/bin/bash

if [ -z "$1" ]; then
  echo "Error: no APK path or pattern provided"
  echo "Usage: $0 <apk-or-pattern>"
  echo "Example: $0 apks/com.ivre.engage/base.apk"
  echo "Example: $0 'apks/com.ivre.engage/*.apk'"
  exit 1
fi

if ! command -v apktool &>/dev/null; then
  echo "Error: apktool not found — brew install apktool"
  exit 1
fi
if ! command -v jadx &>/dev/null; then
  echo "Error: jadx not found — brew install jadx"
  exit 1
fi

unpack_apk() {
  local APK=$1
  local DIR=$(dirname "$APK")
  local NAME=$(basename "$APK" .apk)

  local APKTOOL_OUT="$DIR/$NAME"
  local JADX_OUT="$DIR/jadx/$NAME"

  mkdir -p "$APKTOOL_OUT"
  # Try full decode first. If apktool trips on an unusual AndroidManifest/resource
  # (common NPE on apktool 3.0.x), retry with --no-res — the downstream pipeline
  # only needs lib/ + assets/, which both flags extract.
  if ! apktool d "$APK" -o "$APKTOOL_OUT" -f 2>/dev/null; then
    echo "Warning: apktool full decode failed on $APK — retrying with --no-res"
    rm -rf "$APKTOOL_OUT" && mkdir -p "$APKTOOL_OUT"
    if ! apktool d --no-res "$APK" -o "$APKTOOL_OUT" -f 2>/dev/null; then
      echo "Error: apktool --no-res also failed on $APK"
      return 1
    fi
  fi

  # jadx commonly fails on Unity apps (most classes are stubs) — keep whatever
  # it managed to decompile and continue. Only log failure.
  mkdir -p "$JADX_OUT"
  if ! jadx "$APK" -d "$JADX_OUT" 2>/dev/null; then
    echo "Warning: jadx reported errors on $APK (partial output kept in $JADX_OUT) — continuing"
  fi
}

PATTERN=$1
DIR=$(dirname "$PATTERN")
GLOB=$(basename "$PATTERN")

APKS=()
while IFS= read -r -d $'\0' f; do
  APKS+=("$f")
done < <(find "$DIR" -maxdepth 1 -name "$GLOB" -print0 2>/dev/null)

if [ ${#APKS[@]} -eq 0 ]; then
  echo "Error: no APKs matched '$1'"
  exit 1
fi

echo "Found ${#APKS[@]} APK(s):"
for APK in "${APKS[@]}"; do echo "$APK"; done
for APK in "${APKS[@]}"; do
  unpack_apk "$APK"
done
