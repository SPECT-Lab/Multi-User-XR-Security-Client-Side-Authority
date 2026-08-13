#!/usr/bin/env bash
# setup.sh — prepare the Android device (gadget/server) attack path.
#
# Python is a PREREQUISITE (install it yourself); this script installs the rest:
#   * host Frida (pip, pinned to the bundled gadget)
#   * the runtime logger (frida-il2cpp-bridge bundle)
#   * the bundled Frida gadget/server binaries (decompress)
#   * adb and the gadget-injection toolchain (patchelf, apktool, a JDK for keytool)
#   * checks for the Android SDK build-tools (zipalign, apksigner)
#
# macOS installs missing tools with Homebrew; on Linux the script checks and prints
# the package to install. Toggle: SKIP_TOOL_INSTALL=1 to check only (never install).
#
# (Static analysis — Ghidra / Il2CppDumper — is set up separately, not here.)
set -uo pipefail

FRIDA_VER="17.9.1"
warn=0
note() { printf '  %s\n' "$*"; }
ok()   { printf '  [ OK ] %s\n' "$*"; }
bad()  { printf '  [WARN] %s\n' "$*"; warn=$((warn+1)); }

have() { command -v "$1" >/dev/null 2>&1; }
BREW=""; have brew && BREW=brew

# Ensure a CLI tool exists: on macOS brew-install it (unless SKIP_TOOL_INSTALL=1),
# otherwise print a hint.   ensure_tool <tool> <brew install args> <fallback hint>
ensure_tool() {
  local tool="$1" brewargs="$2" hint="$3"
  if have "$tool"; then ok "$tool ($(command -v "$tool"))"; return 0; fi
  if [ "${SKIP_TOOL_INSTALL:-0}" != "1" ] && [ -n "$BREW" ]; then
    echo "   brew install $brewargs …"
    if brew install $brewargs >/dev/null 2>&1 && have "$tool"; then ok "$tool installed (brew)"; return 0; fi
  fi
  bad "$tool missing — $hint"
  return 1
}

# Find an Android build-tool on PATH or under a standard SDK location.
# Mirrors the search in gadget_injection/inject_frida_gadget.py.
find_buildtool() {
  local name="$1" root ver
  have "$name" && { command -v "$name"; return 0; }
  for root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" \
              "/usr/local/lib/android/sdk" "/opt/android/sdk"; do
    [ -n "$root" ] && [ -d "$root/build-tools" ] || continue
    for ver in $(ls -1r "$root/build-tools" 2>/dev/null); do
      [ -x "$root/build-tools/$ver/$name" ] && { echo "$root/build-tools/$ver/$name"; return 0; }
    done
  done
  return 1
}

echo "== Relay and Betray :: Android device-path setup =="

# 0) Python — PREREQUISITE (not installed here) -------------------------------
echo "-- Python (prerequisite) --"
if have python3; then ok "python3 ($(python3 -V 2>&1))"
else bad "python3 >= 3.10 is a prerequisite — install it first: https://www.python.org/downloads/"; fi

# 1) Host Frida (pip, pinned to the bundled gadget) ---------------------------
echo "-- Host Frida --"
if have python3; then
  echo "   installing requirements.txt (frida $FRIDA_VER)…"
  if python3 -m pip install -r requirements.txt || python3 -m pip install --break-system-packages -r requirements.txt; then
    ok "pip requirements installed"
  else
    bad "pip install failed — install requirements.txt manually (or use a venv)"
  fi
  if python3 -c "import frida" >/dev/null 2>&1; then
    hv="$(python3 -c 'import frida; print(frida.__version__)' 2>/dev/null)"
    if [ "${hv%.*}" = "${FRIDA_VER%.*}" ]; then ok "frida $hv (matches gadget $FRIDA_VER on major.minor)"
    else bad "frida $hv does NOT match gadget $FRIDA_VER"; fi
  fi
fi

# 2) Runtime logger (frida-il2cpp-bridge bundle) ------------------------------
echo "-- Runtime logger --"
if [ -f runtime_logging/runtime_logger.js ]; then
  ok "prebuilt runtime_logging/runtime_logger.js present"
elif have npm; then
  if ( cd runtime_logging && npm install && npm run build ); then ok "built runtime_logging/runtime_logger.js"
  else bad "npm build failed in runtime_logging/"; fi
else
  bad "runtime_logger.js missing and npm not found — install Node.js (https://nodejs.org/) or restore the prebuilt bundle"
fi

# 3) Decompress bundled Frida gadget/server binaries --------------------------
echo "-- Frida gadget/server binaries --"
shopt -s nullglob
for xz in gadget_injection/frida/*.xz; do
  out="${xz%.xz}"
  if [ -e "$out" ]; then note "already decompressed: $(basename "$out")"
  elif unxz -k "$xz" 2>/dev/null; then ok "decompressed $(basename "$xz")"
  else bad "could not decompress $(basename "$xz") (need 'unxz' / xz-utils)"; fi
done
shopt -u nullglob

# 4) adb (device path) --------------------------------------------------------
echo "-- adb --"
ensure_tool adb "--cask android-platform-tools" \
  "Linux: apt-get install android-tools-adb  (or install Android SDK platform-tools)"

# 5) Gadget-injection toolchain (non-rooted) ----------------------------------
echo "-- Gadget-injection tools --"
ensure_tool patchelf patchelf "Linux: apt-get install patchelf"
ensure_tool apktool  apktool  "Linux: apt-get install apktool  (or https://apktool.org)"
# keytool ships with a JDK and must be on PATH for inject_frida_gadget.py
ensure_tool keytool "--cask temurin" "Linux: apt-get install default-jdk  (provides keytool)"

# zipalign / apksigner come with the Android SDK build-tools (no single brew formula);
# best-effort install via the command-line tools + sdkmanager on macOS.
if ! { find_buildtool zipalign >/dev/null && find_buildtool apksigner >/dev/null; }; then
  if [ "${SKIP_TOOL_INSTALL:-0}" != "1" ] && [ -n "$BREW" ]; then
    echo "   installing Android SDK build-tools (brew cask android-commandlinetools + sdkmanager) …"
    brew install --cask android-commandlinetools >/dev/null 2>&1 || true
    if have sdkmanager; then
      yes | sdkmanager --licenses >/dev/null 2>&1 || true
      sdkmanager "build-tools;34.0.0" >/dev/null 2>&1 || true
      bt_root="$(brew --prefix 2>/dev/null)/share/android-commandlinetools"
      [ -d "$bt_root/build-tools" ] && export ANDROID_HOME="${ANDROID_HOME:-$bt_root}"
    fi
  fi
fi
for bt in zipalign apksigner; do
  if p="$(find_buildtool "$bt")"; then ok "$bt ($p)"
  else bad "$bt not found — install Android Studio (SDK build-tools), or set ANDROID_HOME to your SDK"; fi
done
[ -n "${ANDROID_HOME:-}" ] && note "for your shell:  export ANDROID_HOME=\"$ANDROID_HOME\""

echo
if [ "$warn" -gt 0 ]; then
  echo "Setup finished with $warn warning(s) — install the flagged tool(s), then re-run."
else
  echo "All set."
fi
echo "Quick start:  ./android_scripts/inject_and_install.sh <device-serial> <app-package-name>"
