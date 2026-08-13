#!/bin/bash
# Headless Ghidra import of libil2cpp.so with Il2CppDumper symbol restoration.
# Usage: ./run_ghidra_analysis.sh <libil2cpp.so> <dumper-out-dir> [project-dir]
#
# dumper-out-dir must contain il2cpp.h and script.json (from il2cpp_dumper.sh).
# Set GHIDRA_HOME to your Ghidra install if analyzeHeadless is not on PATH.

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <libil2cpp.so> <dumper-out-dir> [project-dir]"
  exit 1
fi

LIB=$1
DUMP_DIR=$2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GHIDRA_SCRIPTS="$SCRIPT_DIR/ghidra_scripts"
PROJECT_DIR=${3:-"$(dirname "$LIB")/ghidra_project"}
EXPORT_DIR="$PROJECT_DIR/export"

if command -v analyzeHeadless &>/dev/null; then
  HEADLESS=$(command -v analyzeHeadless)
elif [ -n "${GHIDRA_HOME:-}" ] && [ -x "$GHIDRA_HOME/support/analyzeHeadless" ]; then
  HEADLESS="$GHIDRA_HOME/support/analyzeHeadless"
else
  echo "analyzeHeadless not found. Install Ghidra and set GHIDRA_HOME."
  exit 1
fi

python3 "$GHIDRA_SCRIPTS/il2cpp_header_to_ghidra.py" "$DUMP_DIR"

mkdir -p "$PROJECT_DIR" "$EXPORT_DIR"

"$HEADLESS" \
  "$PROJECT_DIR" il2cpp \
  -import "$LIB" \
  -overwrite \
  -scriptPath "$GHIDRA_SCRIPTS" \
  -postScript apply_il2cpp.py "$DUMP_DIR/il2cpp_ghidra.h" "$DUMP_DIR/script.json" \
  -postScript export_artifacts.py "$EXPORT_DIR" \
  -log "$PROJECT_DIR/analysis.log"

echo "Done. Project: $PROJECT_DIR  Exports: $EXPORT_DIR"
