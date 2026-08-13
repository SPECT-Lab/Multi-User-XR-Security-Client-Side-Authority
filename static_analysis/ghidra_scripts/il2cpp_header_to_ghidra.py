#!/usr/bin/env python3
# Preprocess Il2CppDumper's il2cpp.h into il2cpp_ghidra.h so Ghidra's C parser
# can ingest it. Adapted from Perfare/Il2CppDumper.
# Usage: python3 il2cpp_header_to_ghidra.py <dumper-out-dir>

import re
import sys
from pathlib import Path

PRELUDE = (
    "typedef unsigned __int8 uint8_t;\n"
    "typedef unsigned __int16 uint16_t;\n"
    "typedef unsigned __int32 uint32_t;\n"
    "typedef unsigned __int64 uint64_t;\n"
    "typedef __int8 int8_t;\n"
    "typedef __int16 int16_t;\n"
    "typedef __int32 int32_t;\n"
    "typedef __int64 int64_t;\n"
    "typedef __int64 intptr_t;\n"
    "typedef __int64 uintptr_t;\n"
    "typedef unsigned __int64 size_t;\n"
    "typedef _Bool bool;\n"
)


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: {} <dumper-out-dir>".format(sys.argv[0]))
    out_dir = Path(sys.argv[1])
    src = out_dir / "il2cpp.h"
    dst = out_dir / "il2cpp_ghidra.h"

    if not src.exists():
        sys.exit("Error: {} not found".format(src))

    text = src.read_text(encoding="utf-8", errors="replace")
    fixed = re.sub(r": (\w+) {", r"{\n \1 super;", text)
    dst.write_text(PRELUDE + fixed, encoding="utf-8")
    print("Wrote {}".format(dst))


if __name__ == "__main__":
    main()
