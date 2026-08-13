# Relay and Betray: Artifact

The artifact contains the reverse engineering pipeline, runtime instrumentation framework, Frida gadget-injection and on-device deployment tooling, Frida attack hook patterns, and attack-demonstration videos for the paper "Relay and Betray: Exploiting Client-Side Trust in Multi-User Mixed Reality".

## Contents

```
.
├── README.md
├── setup.sh
├── setup.ps1
├── requirements.txt
├── android_scripts/
│   ├── pull_apk.sh
│   ├── unpack_apk.sh
│   ├── inject_and_install.sh
│   ├── adb_reinstall.sh
│   ├── start_frida_server.sh
│   ├── frida_rooted.sh
│   ├── hook_gadget.sh
│   └── hook_rooted.sh
├── static_analysis/  
│   ├── il2cpp_dumper.sh
│   ├── run_ghidra_analysis.sh
│   ├── Il2CppDumper/  
│   ├── ghidra_11.3.2_PUBLIC/  
│   └── ghidra_scripts/
│       ├── apply_il2cpp.py
│       ├── export_artifacts.py
│       └── il2cpp_header_to_ghidra.py
├── gadget_injection/              
│   ├── inject_frida_gadget.py
│   ├── patch_tracerpid.sh
│   └── frida/         
├── runtime_logging/         
│   ├── runtime_logger.ts
│   ├── runtime_logger.js          
│   ├── trace_assembly.js
│   ├── package.json
│   ├── package-lock.json
│   └── tsconfig.json
└── attack_hooks/          
    ├── hook_patterns.js
    ├── frida_il2cpp_logging.js
    └── example_attack_hooks/
        ├── video_surveillance.js
        ├── audio_surveillance.js
        └── host_control_evasion.js
```

---

# Components

```
static_analysis/    APK -> Il2CppDumper -> headless Ghidra
gadget_injection/   Embed Frida gadget into an APK
runtime_logging/    Frida scripts for logging runtime behavior of a target app 
attack_hooks/       Frida instrumentation methods and example attack hooks
```

## Static analysis (`static_analysis/`)

Recovers class hierarchies, method signatures, and field names from a Unity IL2CPP APK so they can be analyzed in Ghidra with semantic labels.

- `il2cpp_dumper.sh <unpacked-apk-dir>` — finds `libil2cpp.so` and `global-metadata.dat` inside the unpacked APK and runs Il2CppDumper against them. Outputs `dump.cs`, `script.json`, and `il2cpp.h`.
- `run_ghidra_analysis.sh <libil2cpp.so> <dumper-out-dir>` — runs headless Ghidra import on `libil2cpp.so`, applies the dumper's symbols via `ghidra_scripts/apply_il2cpp.py`, and exports decompiled C per class via `ghidra_scripts/export_artifacts.py`.

`Il2CppDumper/` contains the bundled dumper binaries (Perfare/Il2CppDumper). We patched in support for the newer IL2CPP metadata layouts that recent Unity releases use, which the Il2CppDumper release had not yet caught up with at the time of writing.

Note: Ghidra 11.3.2 is bundled under `static_analysis/ghidra_11.3.2_PUBLIC/`. Set `GHIDRA_HOME` to it (or put `analyzeHeadless` on `PATH`) before running `run_ghidra_analysis.sh`.

## Gadget injection (`gadget_injection/`)

For non-rooted devices (e.g., Quest headsets). On rooted devices, push `frida-server-*.xz` and start it directly instead.

- `inject_frida_gadget.py --apks <base.apk> [splits...] --gadget <gadget.so> --output out/` — rebuilds the APK with the Frida gadget embedded as a `DT_NEEDED` dependency of the entry library. Handles split APK sets, generates a throwaway signing keystore, and bypasses Google PairIP license checks when found.
- `patch_tracerpid.sh <file-or-dir>` — byte-rewrites the string `TracerPid:` to `TracerPax:` in `.so` files, so any `/proc/self/status` anti-debug check silently misses. Apply to the gadget `.so` before injection.
- `frida/` — Frida gadget and server binaries (v17.9.1, arm64).

## Runtime logging (`runtime_logging/`)

Frida scripts for logging runtime behavior of a target app. Logs the class graph, fingerprints networking SDKs (Photon, Fusion, WebRTC, etc.), samples `AudioSource` spatial params, reads `PhotonNetwork` room/master state, and traces outbound `RaiseEvent` traffic.

- `runtime_logger.ts` / `runtime_logger.js` — main logger (TS source + prebuilt bundle).
- `package.json`, `tsconfig.json` — rebuild via `npm install && npm run build`.
- `trace_assembly.js` — trace every method in a named assembly via `Il2Cpp.trace()`.
- `frida_il2cpp_logging.js` — enter/leave log on a single method.

To run:
```
adb forward tcp:27042 tcp:27042
frida -H 127.0.0.1:27042 Gadget -l runtime_logger.js
```

## Attack hooks (`attack_hooks/`)

Generic hook patterns plus example attacks. Fill in the `<...>` placeholders in each example using output from the runtime logger and static analysis.

- `hook_patterns.js` — the four instrumentation methods: modify arguments, modify return value, read/write fields, override method logic.

Examples in `example_attack_hooks/`:
- `video_surveillance.js` — rewrite outbound Photon RaiseEvent codes to suppress pose broadcasts (I1).
- `audio_surveillance.js` — override Unity AudioSource params to defeat spatial-audio falloff (I1).
- `host_control_evasion.js` — no-op kick/summon RPCs and force-clear the seat-lock flag (I3).

## Why We Do Not Release Per-Attack Hooks

As described in our Open Science appendix, we intentionally **do not** release per-app attack scripts with exact method names, offsets, or symbol maps.

**Reasons:**

1. **Ethical considerations and dual use.**  
   The same hooks that demonstrate a vulnerability for research purposes can be misused to attack real users (e.g., stalking, harassment, denial-of-service). Publishing fully bound exploit scripts would substantially lower the barrier for malicious use.

2. **Responsible disclosure.**  
   We have disclosed these issues to the affected vendors and are working within coordinated disclosure timelines. Releasing fully operational exploit code would be inconsistent with that process and could harm users before defenses are deployed.


## Attack Videos

We provide a video demonstration of each attack. All recordings were made in private sessions using only our own test accounts. Some demonstrations include multiple points of view (POVs) captured from different users in the same world (e.g., an attacker, a victim, and a neutral observer) to make the effects of the attack easier to see. Each video is annotated to highlight the key actions and outcomes. Additional technical details about the attacks are available in the paper.

The videos can be found at: https://drive.google.com/drive/folders/1V5h1WPWY368zBUOjq1bUd6bPBc1ai64u?usp=drive_link

---

# Running the Artifact

- **Windows (Desktop)** Frida attaches directly to the desktop build of the target app.
- **Android OS (Quest/Vive/Mobile Device).** Frida-gadget injection for headset and frida-server for rooted Android phone. 

## Windows (Desktop)

**Prerequisites**
- Windows 11 with any modern GPU with >4GB VRAM (renders the client in 2D or desktop mode without a VR headset).
- Python ≥ 3.10 on `PATH`.
- The target app installed

**1. Install dependencies**

From the repo root:

```
powershell -ExecutionPolicy Bypass -File setup.ps1
```

This installs the host Frida pinned to the bundled gadget (`frida==17.9.1` + `frida-tools`) and builds `runtime_logging/runtime_logger.js` (which bundles **frida-il2cpp-bridge** and exposes the `Il2Cpp` global the hooks need). Verify:

```
frida --version        # 17.9.1
```

**2. Find the app's process**

Launch the app in desktop mode, join a private room or world instance, then:

```
frida-ps | Select-String <process_name>
```

**3. Run an attack**

Load the runtime logger **first** (it provides `Il2Cpp`), then the hook; the `-l` order matters:

```
frida -p "<process_id>" \
    -l runtime_logging/runtime_logger.js \
    -l attack_hooks/example_attack_hooks/<hook>.js
```

## Android OS (Quest/Vive/Mobile Device)

**Prerequisites**
- macOS or Linux
- Device connected with USB debugging enabled.
- Python ≥ 3.10 on `PATH` (the only thing you install yourself).
- The target app installed on the device.

**Setup**

Run `./setup.sh` — it installs host Frida, `adb`, `patchelf`, `apktool`, a JDK for `keytool`, and the Android SDK build-tools (`zipalign`, `apksigner`). On macOS it uses Homebrew; on Linux it prints the package to install.

For the following scripts **package name** refers to the package name of the installed app (e.g. `com.android.my_app`), the device **serial** refers to the serial number of the device (e.g., through `adb devices`), and `<hook>` is the path to the attack hook (e.g., `attack_hooks/example_attack_hooks/video_surveillance.js`).

### Non-rooted devices (Quest/Vive)

**1. Pull the APK, add the Frida gadget, and re-install**

```bash
./android_scripts/inject_and_install.sh <device-serial> <app-package-name> [phone|quest]
```

**2. Run the app on the device and find out the process ID**

Launch the patched app, then:

```bash
adb -s <device-serial> shell pidof <app-package-name>
```

**3. Run the attack hook**

Gadget-based attach to run the attack:

```bash
./android_scripts/hook_gadget.sh <device-serial> <app-package-name> attack_hooks/example_attack_hooks/<hook>.js
```

### Rooted device (Mobile device)

**1. Push Frida server to device and start it**

Push the bundled `frida-server` and launch it (requires `su`). With no server argument it uses the bundled `gadget_injection/frida/frida-server-17.9.1-android-arm64`:

```bash
./android_scripts/start_frida_server.sh <device-serial>
```

**2. Run the app on the device and find out the process ID**

Launch the app, then:

```bash
adb -s <device-serial> shell pidof <app-package-name>
```

**3. Run the attack hook**

Attaches over frida-server by PID. Loads the runtime logger then your hook:

```bash
./android_scripts/hook_rooted.sh <device-serial> <app-package-name> attack_hooks/example_attack_hooks/<hook>.js
```

## Static Analysis

Recovers class/method names, signatures, and field offsets from the app's IL2CPP
binary so attack hooks can resolve symbols. **Runs on macOS or Linux.** The binary +
metadata come from either the Windows desktop install or the Android APK.

**Prerequisites**
- macOS or Linux.
- **.NET 6 runtime** — Il2CppDumper is a .NET 6 build. Install it with Microsoft's script (macOS/Linux):
  ```bash
  curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 6.0 --runtime dotnet
  export PATH="$HOME/.dotnet:$PATH"
  ```
- **JDK 21** — Ghidra 11.3.2 needs it. `brew install --cask temurin@21` (Linux: `apt-get install openjdk-21-jdk`).
- **Ghidra 11.3.2** and the patched **Il2CppDumper** are bundled under `static_analysis/` — no download. Point Ghidra's headless runner at the bundle:
  ```bash
  export GHIDRA_HOME="$(pwd)/static_analysis/ghidra_11.3.2_PUBLIC"
  ```

**1. Get `libil2cpp.so` / `GameAssembly.dll` + `global-metadata.dat`**

- **Windows desktop build** (in the install folder):
  - `<install>\GameAssembly.dll`
  - `<install>\<App>_Data\il2cpp_data\Metadata\global-metadata.dat`
- **Android APK** — pull it off the device, then extract (an APK is a zip):
  ```bash
  ./android_scripts/pull_apk.sh <device-serial> <app-package-name> apks/
  unzip 'apks/*.apk' -d unpacked/        # all splits into one folder
  ```
  The files land at:
  - `unpacked/lib/arm64-v8a/libil2cpp.so`  (Quest / 64-bit; 32-bit builds: `lib/armeabi-v7a/libil2cpp.so`)
  - `unpacked/assets/bin/Data/Managed/Metadata/global-metadata.dat`

**2. Run Il2CppDumper**

Point it at the unpacked folder; it finds `libil2cpp.so` + `global-metadata.dat` and writes `dump.cs`, `script.json`, and `il2cpp.h`:

```bash
./static_analysis/il2cpp_dumper.sh <unpacked-apk-dir> [output-dir]
```

For the Windows `GameAssembly.dll`, call the dumper directly:

```bash
dotnet static_analysis/Il2CppDumper/Il2CppDumper.dll GameAssembly.dll global-metadata.dat out/
```

**3. Run Ghidra analysis**

Headless Ghidra import of the binary with the dumper's symbols applied; decompiled C per class is exported to `<project>/export/`:

```bash
./static_analysis/run_ghidra_analysis.sh <libil2cpp.so-or-GameAssembly.dll> <dumper-out-dir>
```

---

## Runtime Logging

Attaches the runtime logger to the **running** app to dump the live class graph,
fingerprint the networking SDK (Photon / Fusion / WebRTC), sample `AudioSource`
params, and trace outbound `RaiseEvent` traffic — the dynamic counterpart to static
analysis, used to fill the `<...>` placeholders in attack hooks. **Runs on macOS or
Linux** against an Android device (loads only the logger, no attack hook).

**Prerequisites**
- The Android device prepared as in **Android OS** above (gadget injected, or frida-server running) and the app launched.

**1. Forward the Frida port and attach the logger**

- **Non-rooted (gadget):**
  ```bash
  adb -s <device-serial> forward tcp:27042 tcp:27042
  frida -H 127.0.0.1:27042 -n Gadget -l runtime_logging/runtime_logger.js | tee runtime.log
  ```
- **Rooted (frida-server):**
  ```bash
  adb -s <device-serial> forward tcp:27042 tcp:27042
  frida -H 127.0.0.1:27042 -p "$(adb -s <device-serial> shell pidof <app-package-name>)" \
      -l runtime_logging/runtime_logger.js | tee runtime.log
  ```

The log lists managed class/method names and SDK fingerprints — use them to fill in the class/method strings the attack hooks need. (On the Windows desktop build, load the same `runtime_logger.js` by itself, as in **Windows (Desktop)** step 3.)

---

## Licensing

The bundled Il2CppDumper binaries are from <https://github.com/Perfare/Il2CppDumper> under their own MIT license. The bundled Frida gadget/server binaries are from <https://github.com/frida/frida> under their wxWindows Library Licence.

