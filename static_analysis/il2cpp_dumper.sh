#!/bin/bash
# Run Il2CppDumper against an unpacked Unity APK directory.
# Usage: ./il2cpp_dumper.sh <unpacked-apk-dir> [output-dir]

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <unpacked-apk-dir> [output-dir]"
  exit 1
fi

DIR=$1
OUT_DIR=${2:-"$DIR/il2cpp_dump"}
DUMPER="$(dirname "$0")/Il2CppDumper/Il2CppDumper.dll"

LIB=$(find "$DIR" -name "libil2cpp.so" -not -path '*/jadx/*' 2>/dev/null | head -1)
METADATA=$(find "$DIR" -name "global-metadata.dat" -not -path '*/jadx/*' 2>/dev/null | head -1)

if [ -z "$LIB" ] || [ -z "$METADATA" ]; then
  echo "Not a Unity IL2CPP app (missing libil2cpp.so or global-metadata.dat)"
  exit 1
fi

mkdir -p "$OUT_DIR"
dotnet "$DUMPER" "$LIB" "$METADATA" "$OUT_DIR" </dev/null

echo "Dump written to $OUT_DIR"
ls "$OUT_DIR/"
