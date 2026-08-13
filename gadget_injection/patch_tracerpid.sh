#!/bin/bash
# Patch the "TracerPid:" string in shared libraries to "TracerPax:" so any
# /proc/self/status anti-debug check silently misses. Apply to a .so file
# (or all .so under a directory) before APK injection.
#
# Usage: ./patch_tracerpid.sh <file-or-dir>

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <file-or-dir>"
  exit 1
fi

TARGET=$1
total=0

patch_one() {
  local f=$1
  local n
  n=$(python3 -c '
import sys, pathlib
p = pathlib.Path(sys.argv[1])
d = p.read_bytes()
n = d.count(b"TracerPid:")
if n:
    p.write_bytes(d.replace(b"TracerPid:", b"TracerPax:"))
print(n)' "$f")
  if [ "$n" -gt 0 ]; then
    echo "  patched $f ($n occurrences)"
    total=$((total + n))
  fi
}

if [ -f "$TARGET" ]; then
  patch_one "$TARGET"
elif [ -d "$TARGET" ]; then
  while IFS= read -r f; do
    patch_one "$f"
  done < <(find "$TARGET" -name "*.so" 2>/dev/null)
else
  echo "Not a file or directory: $TARGET"
  exit 1
fi

echo "Total patches: $total"
