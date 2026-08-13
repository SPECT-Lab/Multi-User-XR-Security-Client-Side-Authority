#!/usr/bin/env python3
# Inject a Frida gadget into an Android APK and re-sign. Handles split APK sets
# and bypasses Google PairIP license checks when present.
#
# Usage:
#   python3 inject_frida_gadget.py --apks base.apk [splits...] \
#       --gadget frida/frida-gadget-*-android-arm64.so --output out/

import argparse, json, os, re, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path


ENTRY_CANDIDATES = [
    "libmain.so", "libunity.so", "libUnreal.so", "libUE4.so",
    "libmonodroid.so", "libnative-lib.so", "libapp.so", "libflutter.so",
]
ABI = "lib/arm64-v8a"

GADGET = "libfrida-gadget.so"
GADGET_CFG = "libfrida-gadget.config.so"

GADGET_CFG_JSON = {
    "interaction": {"type": "listen", "address": "127.0.0.1",
                    "port": 27042, "on_load": "resume"}
}

KS_PASS = "testpass"
KS_ALIAS = "testkey"
KS_DNAME = "CN=Test, OU=Test, O=Test, L=Test, S=Test, C=US"


def sh(*cmd, capture=False, check=True):
    return subprocess.run(list(cmd), check=check,
                          capture_output=capture, text=capture)


def find_tool(name):
    if p := shutil.which(name):
        return p
    roots = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
             str(Path.home() / "Library/Android/sdk"),
             "/usr/local/lib/android/sdk", "/opt/android/sdk"]
    for r in roots:
        if not r:
            continue
        bt = Path(r) / "build-tools"
        if not bt.is_dir():
            continue
        for ver in sorted(bt.iterdir(), reverse=True):
            if (ver / name).exists():
                return str(ver / name)
    sys.exit("Required tool not found: {}".format(name))


def find_entry_lib(apk):
    with zipfile.ZipFile(apk) as z:
        names = z.namelist()
    for cand in ENTRY_CANDIDATES:
        for n in names:
            if n.endswith(f"/{cand}"):
                return n
    return None


def has_native_libs(apk):
    with zipfile.ZipFile(apk) as z:
        return any(n.startswith("lib/") and n.endswith(".so") for n in z.namelist())


def has_dex(apk):
    with zipfile.ZipFile(apk) as z:
        return any(n.endswith(".dex") for n in z.namelist())


def has_pairip(apk):
    with zipfile.ZipFile(apk) as z:
        for n in z.namelist():
            if n.endswith(".dex") and b"pairip" in z.read(n):
                return True
    return False


def apk_package(apk, aapt2):
    if aapt2:
        out = sh(aapt2, "dump", "badging", str(apk), capture=True, check=False).stdout
        if m := re.search(r"package: name='([^']+)'", out):
            return m.group(1)
    with zipfile.ZipFile(apk) as z:
        if "AndroidManifest.xml" in z.namelist():
            if m := re.search(rb'com\.[a-zA-Z0-9._]+', z.read("AndroidManifest.xml")):
                return m.group(0).decode()
    return "unknown"


def cert_sha256(apk, apksigner):
    out = sh(apksigner, "verify", "--print-certs", str(apk),
             capture=True, check=False).stdout
    for line in out.splitlines():
        if "SHA-256" in line:
            return line.split(":")[-1].strip()
    return ""


def make_keystore(path):
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    sh("keytool", "-genkey", "-v",
       "-keystore", str(path), "-alias", KS_ALIAS,
       "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
       "-storepass", KS_PASS, "-keypass", KS_PASS, "-dname", KS_DNAME)


def write_gadget_cfg(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(GADGET_CFG_JSON, indent=2))


def add_dt_needed(so_path):
    cur = sh("patchelf", "--print-needed", str(so_path), capture=True).stdout
    if GADGET in cur:
        return
    sh("patchelf", "--add-needed", GADGET, str(so_path))
    cur = sh("patchelf", "--print-needed", str(so_path), capture=True).stdout
    if GADGET not in cur:
        sys.exit("patchelf failed to add {} to {}".format(GADGET, so_path))


# Files Android requires uncompressed
_STORED_EXT = {".so", ".arsc", ".dex", ".png"}
_STORED_PREFIX = ("assets/bin/Data/",)


def _stored(entry):
    return (Path(entry).suffix in _STORED_EXT
            or any(entry.startswith(p) for p in _STORED_PREFIX))


def repack_lib_apk(src_apk, gadget_so, gadget_cfg, dst_unsigned):
    entry = find_entry_lib(src_apk)
    if not entry:
        sys.exit("No entry library in {} (looked for {})".format(
            src_apk.name, ENTRY_CANDIDATES))

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        with zipfile.ZipFile(src_apk) as z:
            z.extractall(td)
            keep = [n for n in z.namelist()
                    if not n.startswith("META-INF/")
                    and n not in (f"{ABI}/{GADGET}", f"{ABI}/{GADGET_CFG}")]

        add_dt_needed(td / entry)

        abi_dir = td / ABI
        shutil.copy2(gadget_so, abi_dir / GADGET)
        shutil.copy2(gadget_cfg, abi_dir / GADGET_CFG)

        dst_unsigned.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(dst_unsigned, "w") as zout:
            for n in keep:
                p = td / n
                if not p.exists():
                    continue
                ct = zipfile.ZIP_STORED if _stored(n) else zipfile.ZIP_DEFLATED
                zout.write(p, n, compress_type=ct)
            for f in (GADGET, GADGET_CFG):
                zout.write(abi_dir / f, f"{ABI}/{f}", compress_type=zipfile.ZIP_STORED)


# PairIP license check bypass (Google Play Integrity)
PAIRIP_PATCHES = [
    ("com/pairip/licensecheck/LicenseClient.smali",
     ".method public initializeLicenseCheck()V",
     ".method public initializeLicenseCheck()V\n    .locals 0\n\n"
     "    # FRIDA_INJECT: bypass\n    return-void\n\n"),

    ("com/pairip/licensecheck/LicenseActivity.smali",
     ".method public onStart()V",
     ".method public onStart()V\n    .locals 2\n\n"
     "    # FRIDA_INJECT: bypass\n"
     "    invoke-super {p0}, Landroid/app/Activity;->onStart()V\n\n"
     "    invoke-virtual {p0}, Lcom/pairip/licensecheck/LicenseActivity;->finish()V\n\n"
     "    return-void\n\n"),

    ("com/pairip/licensecheck/LicenseContentProvider.smali",
     ".method public onCreate()Z",
     ".method public onCreate()Z\n    .locals 1\n\n"
     "    # FRIDA_INJECT: bypass\n    const/4 v0, 0x1\n    return v0\n\n"),
]


def bypass_pairip(decoded, device):
    for relpath, sig, body in PAIRIP_PATCHES:
        if relpath.endswith("LicenseContentProvider.smali") and device != "phone":
            continue
        for smali_root in sorted(decoded.glob("smali*")):
            f = smali_root / relpath
            if not f.exists():
                continue
            txt = f.read_text()
            if "# FRIDA_INJECT: bypass" in txt:
                continue
            new = re.sub(re.escape(sig) + r"\n(\s+\.locals \d+\n)",
                         body, txt, count=1)
            if new != txt:
                f.write_text(new)


def repack_base_apk(src_apk, dst_unsigned, patch_pairip, device, apktool):
    dst_unsigned.parent.mkdir(parents=True, exist_ok=True)

    if patch_pairip:
        with tempfile.TemporaryDirectory() as td:
            decoded = Path(td) / "d"
            sh(apktool, "d", str(src_apk), "-o", str(decoded), "-f")
            bypass_pairip(decoded, device)
            sh(apktool, "b", str(decoded), "-o", str(dst_unsigned))
        return

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        with zipfile.ZipFile(src_apk) as z:
            z.extractall(td)
            keep = [n for n in z.namelist() if not n.startswith("META-INF/")]
        with zipfile.ZipFile(dst_unsigned, "w") as zout:
            for n in keep:
                p = td / n
                if not p.exists() or p.is_dir():
                    continue
                ct = zipfile.ZIP_STORED if _stored(n) else zipfile.ZIP_DEFLATED
                zout.write(p, n, compress_type=ct)


def sign(unsigned, signed, keystore, zipalign, apksigner):
    aligned = signed.with_suffix(".aligned.apk")
    aligned.unlink(missing_ok=True)
    sh(zipalign, "-v", "4", str(unsigned), str(aligned))
    sh(apksigner, "sign", "--ks", str(keystore),
       "--ks-pass", f"pass:{KS_PASS}", "--key-pass", f"pass:{KS_PASS}",
       "--out", str(signed), str(aligned))
    aligned.unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apks", nargs="+", required=True)
    ap.add_argument("--gadget", required=True)
    ap.add_argument("--output", default="./frida_output")
    ap.add_argument("--keystore", default=None)
    ap.add_argument("--no-pairip-bypass", action="store_true")
    ap.add_argument("--device-type", choices=["phone", "quest"], default="phone")
    a = ap.parse_args()

    apks = [Path(p).resolve() for p in a.apks]
    gadget_so = Path(a.gadget).resolve()
    out = Path(a.output).resolve()
    keystore = Path(a.keystore).resolve() if a.keystore else out / "keystore/test.keystore"

    for p in apks:
        if not p.exists():
            sys.exit("Missing APK: {}".format(p))
    if not gadget_so.exists():
        sys.exit("Missing gadget .so: {}".format(gadget_so))

    out.mkdir(parents=True, exist_ok=True)

    find_tool("patchelf")
    zipalign = find_tool("zipalign")
    apksigner = find_tool("apksigner")
    find_tool("keytool")
    apktool = shutil.which("apktool")
    aapt2 = shutil.which("aapt2")

    make_keystore(keystore)
    cfg = out / GADGET_CFG
    write_gadget_cfg(cfg)

    role = {}
    for apk in apks:
        if has_native_libs(apk) and has_dex(apk):
            role[apk] = "monolithic"
        elif has_native_libs(apk):
            role[apk] = "lib"
        elif has_dex(apk):
            role[apk] = "base"
        else:
            role[apk] = "assets"

    do_pairip = False
    if not a.no_pairip_bypass:
        for apk, r in role.items():
            if r in ("base", "monolithic") and has_pairip(apk):
                do_pairip = True
                break
    if do_pairip and not apktool:
        sys.exit("apktool required for PairIP bypass")

    signed_outs = []
    fingerprints = []

    for apk, r in role.items():
        stem = apk.stem
        unsigned = out / f"{stem}_unsigned.apk"
        signed = out / f"{stem}_signed.apk"

        if r == "lib":
            repack_lib_apk(apk, gadget_so, cfg, unsigned)

        elif r == "base":
            repack_base_apk(apk, unsigned, do_pairip, a.device_type, apktool)

        elif r == "monolithic":
            lib_only = out / f"{stem}_lib_unsigned.apk"
            repack_lib_apk(apk, gadget_so, cfg, lib_only)
            if do_pairip:
                with tempfile.TemporaryDirectory() as td:
                    decoded = Path(td) / "d"
                    sh(apktool, "d", str(apk), "-o", str(decoded), "-f")
                    bypass_pairip(decoded, a.device_type)
                    (decoded / ABI).mkdir(parents=True, exist_ok=True)
                    with zipfile.ZipFile(lib_only) as z:
                        for n in z.namelist():
                            if n.startswith(f"{ABI}/"):
                                z.extract(n, decoded)
                    sh(apktool, "b", str(decoded), "-o", str(unsigned))
                lib_only.unlink(missing_ok=True)
            else:
                lib_only.rename(unsigned)

        else:
            with zipfile.ZipFile(apk) as zin, zipfile.ZipFile(unsigned, "w") as zout:
                for info in zin.infolist():
                    if info.filename.startswith("META-INF/"):
                        continue
                    zout.writestr(info, zin.read(info.filename))

        sign(unsigned, signed, keystore, zipalign, apksigner)
        unsigned.unlink(missing_ok=True)
        signed_outs.append(signed)
        fingerprints.append(cert_sha256(signed, apksigner))

    if len(set(fingerprints)) != 1:
        print("Warning: APKs have mismatched signing certs:")
        for apk, fp in zip(signed_outs, fingerprints):
            print("  {}: {}".format(apk.name, fp))

    pkg = apk_package(apks[0], aapt2)
    print("\nOutput:")
    for s in signed_outs:
        print("  {}".format(s))
    print("\nInstall:")
    print("  adb uninstall {}".format(pkg))
    if len(signed_outs) == 1:
        print("  adb install {}".format(signed_outs[0]))
    else:
        print("  adb install-multiple " + " ".join(str(s) for s in signed_outs))
    print("\nAttach:")
    print("  adb forward tcp:27042 tcp:27042 && frida -H 127.0.0.1:27042 Gadget")


if __name__ == "__main__":
    main()
