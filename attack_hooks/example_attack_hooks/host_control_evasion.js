// Host control evasion example (I3) — ignore inbound host moderation RPCs.
//
// Goal: stay in the room and move freely regardless of host commands.
// Targets the three host controls described in the paper (Section 5.2.2):
//   - kick:      forced removal from the session
//   - summon:    forced teleport to the host's location
//   - seat lock: forced immobilization in a seat (e.g. during a lecture)
//
// Two patterns are shown:
//   Pattern B (no-op replacement) — for inbound RPC handlers. The local
//     client logs the command and takes no action. Used for kick and
//     summon, where the entire RPC should be discarded.
//   Pattern III (field write) — for state flags set by the RPC handler.
//     Used as an alternative for seat lock: instead of (or in addition to)
//     no-op'ing the RPC, the local client forces the lock boolean back to
//     false after the original handler ran.
//
// Per-app discovery: use the runtime logger's class probe to find the
// central RPC handler class (usually contains many `RPC_*` methods or
// equivalents). Identify the specific handler method names plus the
// seat-lock flag field on the seat manager. Fill in CONFIG.

'use strict';

const CONFIG = {
  RPC_HANDLER_CLASS:    '<RPC_HANDLER_CLASS>',
  SEAT_MANAGER_CLASS:   '<SEAT_MANAGER_CLASS>',
  SEAT_LOCK_SETTER:     '<SEAT_LOCK_SETTER>',   

  BYPASS_KICK:          true,
  BYPASS_SUMMON:        true,
  BYPASS_SEAT_LOCK:     true,

  LOG_LIMIT:            200,
};

const RPC_TARGETS = [
  { method: '<KICK_HANDLER>',   arity: 0, bypass: CONFIG.BYPASS_KICK   },
  { method: '<SUMMON_HANDLER>', arity: 5, bypass: CONFIG.BYPASS_SUMMON },
];


let logCount = 0;
function logLine(msg) {
  if (logCount < CONFIG.LOG_LIMIT) { logCount++; console.log(msg); }
}

function findClass(fullName) {
  for (const assembly of Il2Cpp.domain.assemblies) {
    const klass = assembly.image.tryClass(fullName);
    if (klass) return { assembly, klass };
  }
  return null;
}

function resolveMethod(className, methodName, parameterCount) {
  const found = findClass(className);
  if (!found) return null;
  let m = found.klass.tryMethod(methodName, parameterCount);
  if (!m) {
    const matches = found.klass.methods.filter(x => x.name === methodName);
    if (matches.length === 1) m = matches[0];
    else return null;
  }
  return { klass: found.klass, method: m };
}

function safeMethodAddr(method) {
  try { const va = method.virtualAddress; if (!va.isNull()) return va; } catch (_) {}
  try { const fp = method.handle.readPointer(); if (!fp.isNull()) return fp; } catch (_) {}
  return null;
}


// Pattern B: replace the handler's implementation with a no-op.
function bypassRpc(target, label) {
  if (!target) { logLine(`[host-bypass] target not found: ${label}`); return; }
  try {
    target.method.implementation = function () {
      logLine(`[host-bypass] blocked ${label}`);
    };
    logLine(`[host-bypass] no-op installed on ${label}`);
  } catch (e) {
    logLine(`[host-bypass] no-op failed on ${label}: ${e.message}`);
  }
}

// Pattern III: hook the seat-lock setter and force the flag back to false.
function bypassSeatLockSetter(target, label) {
  if (!target) { logLine(`[host-bypass] target not found: ${label}`); return; }
  const addr = safeMethodAddr(target.method);
  if (!addr) return;
  try {
    Interceptor.attach(addr, {
      onEnter(args) {
        // args[0] = `this`, args[1] = new boolean value
        const requested = !args[1].isNull() && args[1].toUInt32() !== 0;
        if (requested) {
          args[1] = ptr(0);
          logLine(`[host-bypass] ${label} forced false`);
        }
      }
    });
    logLine(`[host-bypass] flag-rewrite installed on ${label}`);
  } catch (e) {
    logLine(`[host-bypass] flag-rewrite failed on ${label}: ${e.message}`);
  }
}


Il2Cpp.perform(() => {
  for (const t of RPC_TARGETS) {
    if (!t.bypass) continue;
    const m = resolveMethod(CONFIG.RPC_HANDLER_CLASS, t.method, t.arity);
    bypassRpc(m, `${t.method}/${t.arity}`);
  }

  if (CONFIG.BYPASS_SEAT_LOCK) {
    const setter = resolveMethod(CONFIG.SEAT_MANAGER_CLASS, CONFIG.SEAT_LOCK_SETTER, 1);
    bypassSeatLockSetter(setter, CONFIG.SEAT_LOCK_SETTER);
  }
});