# Ghidra headless post-script: export decompiled C, function index, strings,
# and symbols from the open program. Runs after apply_il2cpp.py.
#
# Usage (via run_ghidra_analysis.sh):
#   -postScript export_artifacts.py <out-dir> [timeout-s] [threads]
#
# Output:
#   index.json     - per-function metadata (name, addr, size, callers, callees)
#   strings.json   - defined strings with xrefs
#   symbols.json   - {address: name}
#   decomp/<class>/<method>_<addr>.c
#
# @runtime Jython
import json
import os
import re

from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.program.util import DefinedDataIterator
from ghidra.util.task import TaskMonitor

from java.util.concurrent import (
    Executors,
    ExecutorCompletionService,
    ArrayBlockingQueue,
    Callable,
)

args = getScriptArgs()
if len(args) < 1:
    raise Exception("Usage: -postScript export_artifacts.py <out-dir> [timeout-s] [threads]")

out_dir = args[0]
timeout = int(args[1]) if len(args) >= 2 else 30
num_workers = int(args[2]) if len(args) >= 3 else 4

decomp_dir = os.path.join(out_dir, "decomp")
for d in (out_dir, decomp_dir):
    if not os.path.isdir(d):
        os.makedirs(d)

fm = currentProgram.getFunctionManager()
refman = currentProgram.getReferenceManager()
symtab = currentProgram.getSymbolTable()

_SAFE = re.compile(r"[^A-Za-z0-9_.\-]+")


def sanitize(s, maxlen=180):
    s = _SAFE.sub("_", s)
    if len(s) > maxlen:
        s = s[:maxlen]
    return s or "_"


def class_bucket(name):
    for sep in ("$$", "::", "."):
        if sep in name:
            head = name.rsplit(sep, 1)[0]
            return sanitize(head, 120) or "_"
    return "_root"


# Collect named functions
targets = []
for fn in fm.getFunctions(True):
    n = fn.getName()
    if n.startswith("FUN_") or n.startswith("thunk_FUN_"):
        continue
    targets.append(fn)

# Pre-create bucket dirs
buckets = set()
for fn in targets:
    buckets.add(class_bucket(fn.getName()))
for b in buckets:
    p = os.path.join(decomp_dir, b)
    if not os.path.isdir(p):
        os.makedirs(p)

# DecompInterface pool
iface_pool = ArrayBlockingQueue(num_workers)
for _ in range(num_workers):
    d = DecompInterface()
    d.setOptions(DecompileOptions())
    d.openProgram(currentProgram)
    iface_pool.put(d)


def process_function(iface, func):
    name = func.getName()
    entry = func.getEntryPoint()
    addr_str = entry.toString()

    callers = []
    try:
        for r in refman.getReferencesTo(entry):
            if r.getReferenceType().isCall():
                callers.append(r.getFromAddress().toString())
                if len(callers) >= 50:
                    break
    except:
        pass

    callees = []
    try:
        for called in func.getCalledFunctions(TaskMonitor.DUMMY):
            callees.append(called.getEntryPoint().toString())
            if len(callees) >= 50:
                break
    except:
        pass

    rel_file = None
    try:
        res = iface.decompileFunction(func, timeout, TaskMonitor.DUMMY)
        if res.decompileCompleted():
            c_src = res.getDecompiledFunction().getC()
            bucket = class_bucket(name)
            fpath = os.path.join(decomp_dir, bucket, sanitize(name) + "_" + addr_str + ".c")
            f = open(fpath, "w")
            try:
                f.write("// {}\n// addr: {}\n\n".format(name, addr_str))
                f.write(c_src)
            finally:
                f.close()
            rel_file = os.path.relpath(fpath, out_dir)
    except:
        pass

    return {
        "name": name,
        "address": addr_str,
        "size": func.getBody().getNumAddresses(),
        "file": rel_file,
        "callers": callers,
        "callees": callees,
    }


class DecompTask(Callable):
    def __init__(self, func):
        self.func = func

    def call(self):
        iface = iface_pool.take()
        try:
            return process_function(iface, self.func)
        finally:
            iface_pool.put(iface)


executor = Executors.newFixedThreadPool(num_workers)
ecs = ExecutorCompletionService(executor)

try:
    for fn in targets:
        ecs.submit(DecompTask(fn))

    index = []
    for i in range(len(targets)):
        entry = ecs.take().get()
        index.append(entry)
finally:
    executor.shutdown()

f = open(os.path.join(out_dir, "index.json"), "w")
try:
    json.dump(index, f, indent=1)
finally:
    f.close()

# Strings
strings = []
try:
    for data in DefinedDataIterator.definedStrings(currentProgram):
        addr = data.getAddress()
        val = data.getValue()
        if val is None:
            continue
        xrefs = []
        try:
            for r in refman.getReferencesTo(addr):
                xrefs.append(r.getFromAddress().toString())
                if len(xrefs) >= 20:
                    break
        except:
            pass
        strings.append({
            "address": addr.toString(),
            "value": unicode(val) if not isinstance(val, unicode) else val,
            "xrefs": xrefs,
        })
except Exception as e:
    print("strings collection error: {}".format(e))

f = open(os.path.join(out_dir, "strings.json"), "w")
try:
    json.dump(strings, f, indent=1, ensure_ascii=False)
finally:
    f.close()

# Symbols
symbols = {}
try:
    for sym in symtab.getAllSymbols(False):
        symbols[sym.getAddress().toString()] = sym.getName()
except Exception as e:
    print("symbols collection error: {}".format(e))

f = open(os.path.join(out_dir, "symbols.json"), "w")
try:
    json.dump(symbols, f, indent=1)
finally:
    f.close()

print("done: {} functions, {} strings, {} symbols".format(
    len(index), len(strings), len(symbols)))
