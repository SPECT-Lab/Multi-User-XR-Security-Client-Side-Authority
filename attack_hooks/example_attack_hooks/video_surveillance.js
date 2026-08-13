// Video surveillance example (I1) — suppress outbound pose broadcasting.
//
// Goal: peers see the attacker's avatar as stationary while the attacker
// roams freely with full local rendering.
//
// Two general mechanisms exist; this example shows Mechanism A.
//   A. Photon RaiseEvent rewrite (Pattern A in hook_patterns.js)
//      For apps where pose is broadcast through Photon's standard event
//      system. Hook RaiseEvent / RaiseEventInternal and rewrite the
//      outbound event code on the pose-carrying event so peers drop it.
//   B. Native RET patch (Pattern C in hook_patterns.js)
//      For apps with their own movement broadcaster. Identify the local
//      method that publishes pose each frame (e.g. an UpdateMovementData
//      called from LateUpdate) and overwrite its first instruction with
//      ARM64 RET (0xD65F03C0). The local CharacterController is untouched.
//
// Per-app discovery (Mechanism A): run the runtime logger's RaiseEvent
// trace to find which event code carries pose. For Photon's generic
// code 1, the subtype byte sits at key [0] of the payload Hashtable.

'use strict';

const CONFIG = {
  BLOCK_CODES:           [],     // event codes carrying pose
  BLOCK_CODE1_SUBTYPES:  [],     // subtype bytes for code-1 events; empty = match all
  REMAP_CODE:            250,    // code peers won't recognize
  NULL_CONTENT:          true,
  LOG_LIMIT:             200,
};


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

function safeMethodAddr(method) {
  try { const va = method.virtualAddress; if (!va.isNull()) return va; } catch (_) {}
  try { const fp = method.handle.readPointer(); if (!fp.isNull()) return fp; } catch (_) {}
  return null;
}


Il2Cpp.perform(() => {
  const photonNetwork = findClass('Photon.Pun.PhotonNetwork');
  if (!photonNetwork) {
    throw new Error('Photon.Pun.PhotonNetwork not loaded');
  }

  const raiseEvent         = photonNetwork.klass.tryMethod('RaiseEvent', 4);
  const raiseEventInternal = photonNetwork.klass.tryMethod('RaiseEventInternal', 4);

  function getHashtableSubtype(contentPtr) {
    if (contentPtr.isNull()) return null;
    try {
      const content = new Il2Cpp.Object(contentPtr);
      if (content.class.fullName !== 'ExitGames.Client.Photon.Hashtable') return null;
      const keyZero = Il2Cpp.boxed(0, 'uint8');
      const value = content.method('get_Item', 1).invoke(keyZero);
      if (value == null) return null;
      const boxed = value instanceof Il2Cpp.Object ? value : new Il2Cpp.Object(value.handle ?? value);
      return parseInt(boxed.toString(), 10);
    } catch {
      return null;
    }
  }

  function install(method, label) {
    if (!method) return;
    const addr = safeMethodAddr(method);
    if (!addr) return;

    Interceptor.attach(addr, {
      onEnter(args) {
        const code = args[0].toUInt32() & 0xff;
        if (CONFIG.BLOCK_CODES.indexOf(code) === -1) return;

        const subtype = code === 1 ? getHashtableSubtype(args[1]) : null;
        if (code === 1
            && CONFIG.BLOCK_CODE1_SUBTYPES.length > 0
            && CONFIG.BLOCK_CODE1_SUBTYPES.indexOf(subtype) === -1) {
          return;
        }

        args[0] = ptr(CONFIG.REMAP_CODE);
        if (CONFIG.NULL_CONTENT) args[1] = NULL;

        logLine(
          `[video-surv] ${label} code=${code}` +
          (subtype !== null ? ` subtype=${subtype}` : '') +
          ` -> ${CONFIG.REMAP_CODE}`
        );
      }
    });
  }

  install(raiseEvent,         'PhotonNetwork.RaiseEvent/4');
  install(raiseEventInternal, 'PhotonNetwork.RaiseEventInternal/4');
});
