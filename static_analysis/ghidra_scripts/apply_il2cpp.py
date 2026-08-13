# Ghidra headless post-script: parse il2cpp_ghidra.h into the DataTypeManager,
# then apply symbols and signatures from Il2CppDumper's script.json.
# Adapted from Perfare/Il2CppDumper's ghidra_with_struct.py.
#
# Usage (via run_ghidra_analysis.sh):
#   -postScript apply_il2cpp.py <il2cpp_ghidra.h> <script.json>
#
# @runtime Jython
import json

from ghidra.app.util.cparser.C import CParser, CParserUtils
from ghidra.app.cmd.function import ApplyFunctionSignatureCmd
import ghidra.program.model.symbol.SourceType as SourceType

args = getScriptArgs()
if len(args) < 2:
    raise Exception("Usage: -postScript apply_il2cpp.py <il2cpp_ghidra.h> <script.json>")

header_path = args[0]
script_path = args[1]

USER_DEFINED = SourceType.USER_DEFINED
dtm = currentProgram.getDataTypeManager()
baseAddress = currentProgram.getImageBase()

# Parse header into DataTypeManager
parser = CParser(dtm, True, None)
parser.setParseFileName(header_path)
try:
    f = open(header_path, "r")
    try:
        parser.parse(f.read())
    finally:
        f.close()
except Exception as e:
    print("Header parse warning: {}".format(e))


def get_addr(addr):
    return baseAddress.add(addr)


def set_name(addr, name):
    try:
        createLabel(addr, name.replace(" ", "-"), True, USER_DEFINED)
    except:
        pass


def set_type(addr, typ):
    newType = typ.replace("*", " *").replace("  ", " ").strip()
    dataTypes = getDataTypes(newType)
    addrType = None
    if len(dataTypes) == 0:
        if newType.endswith(" *"):
            base = newType[:-2]
            bd = getDataTypes(base)
            if len(bd) == 1:
                addrType = dtm.addDataType(dtm.getPointer(bd[0]), None)
    elif len(dataTypes) > 1:
        return
    else:
        addrType = dataTypes[0]
    if addrType is not None:
        try:
            createData(addr, addrType)
        except:
            pass


def make_function(start):
    if getFunctionAt(start) is None:
        try:
            createFunction(start, None)
        except:
            pass


def set_sig(addr, name, sig):
    typeSig = None
    try:
        typeSig = CParserUtils.parseSignature(None, currentProgram, sig, False)
    except:
        try:
            newSig = sig.replace(", ", "ext, ").replace(")", "ext)")
            typeSig = CParserUtils.parseSignature(None, currentProgram, newSig, False)
        except:
            return
    if typeSig is not None:
        try:
            typeSig.setName(name)
            ApplyFunctionSignatureCmd(addr, typeSig, USER_DEFINED, False, True).applyTo(currentProgram)
        except:
            pass


# Apply script.json
f = open(script_path, "rb")
try:
    data = json.loads(f.read().decode("utf-8"))
finally:
    f.close()

if "ScriptMethod" in data:
    for m in data["ScriptMethod"]:
        set_name(get_addr(m["Address"]), m["Name"].encode("utf-8"))

if "ScriptString" in data:
    for idx, s in enumerate(data["ScriptString"], start=1):
        a = get_addr(s["Address"])
        createLabel(a, "StringLiteral_" + str(idx), True, USER_DEFINED)
        setEOLComment(a, s["Value"].encode("utf-8"))

if "ScriptMetadata" in data:
    for m in data["ScriptMetadata"]:
        a = get_addr(m["Address"])
        n = m["Name"].encode("utf-8")
        set_name(a, n)
        setEOLComment(a, n)
        if m.get("Signature"):
            set_type(a, m["Signature"].encode("utf-8"))

if "ScriptMetadataMethod" in data:
    for m in data["ScriptMetadataMethod"]:
        a = get_addr(m["Address"])
        n = m["Name"].encode("utf-8")
        set_name(a, n)
        setEOLComment(a, n)

if "Addresses" in data:
    addrs = data["Addresses"]
    for i in range(len(addrs) - 1):
        make_function(get_addr(addrs[i]))

if "ScriptMethod" in data:
    for m in data["ScriptMethod"]:
        a = get_addr(m["Address"])
        sig = m["Signature"][:-1].encode("utf-8")
        set_sig(a, m["Name"].encode("utf-8"), sig)
