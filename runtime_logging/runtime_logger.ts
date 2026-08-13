// Frida logger for Unity IL2CPP apps. Inventories classes,
// fingerprints networking SDKs, samples AudioSource state, probes
// moderation classes, traces Photon RaiseEvent calls.
//
// Build: npm install && npm run build
// Run:   adb forward tcp:27042 tcp:27042
//        frida -H 127.0.0.1:27042 Gadget -l runtime_logger.js

import "frida-il2cpp-bridge";

const CFG = {
  topNs: 20,
  audioCap: 200,
  tickMs: 10000,
  rpcCap: 500,

  fingerprints: [
    "Photon.Pun", "Photon.Realtime", "Photon.Voice", "Photon.Chat",
    "Fusion", "Mirror", "Unity.Netcode", "Unity.WebRTC", "MediaSoup",
    "Oculus.Platform", "Oculus.Avatar2", "ReadyPlayerMe", "Dissonance",
    "Vivox", "Agora", "PlayFab", "DarkRift", "SocketIO", "SignalR",
  ],

  probes: [
    "PhotonNetwork", "PhotonView", "PhotonVoiceNetwork",
    "NetworkManager", "AvatarController", "AvatarManager",
    "BlockingController", "ModerationManager", "BlocksModel", "DissonanceComms",
  ],

  enumerate: [] as string[],
};

const log = (t: string, m: string) =>
  console.log(`[${new Date().toISOString().slice(11, 23)}][${t}] ${m}`);

const tryGet = (fn: () => any) => { try { return fn(); } catch { return null; } };

function getClass(name: string): Il2Cpp.Class | null {
  for (const a of Il2Cpp.domain.assemblies)
    for (const k of a.image.classes) if (k.name === name) return k;
  return null;
}


function inventory() {
  const ns = new Map<string, number>();
  let total = 0;
  for (const a of Il2Cpp.domain.assemblies)
    for (const k of a.image.classes) {
      total++;
      const n = k.namespace || "<global>";
      ns.set(n, (ns.get(n) || 0) + 1);
    }
  log("inv", `${total} classes / ${Il2Cpp.domain.assemblies.length} assemblies`);
  for (const [n, c] of [...ns.entries()].sort((a, b) => b[1] - a[1]).slice(0, CFG.topNs))
    log("inv", `  ${String(c).padStart(5)}  ${n}`);
  return ns;
}

function fingerprints(ns: Map<string, number>) {
  for (const fp of CFG.fingerprints) {
    let n = 0;
    for (const [k, c] of ns) if (k === fp || k.startsWith(fp + ".")) n += c;
    if (n) log("sdk", `${fp}*  (${n})`);
  }
}

function probes() {
  for (const name of CFG.probes) {
    const k = getClass(name);
    if (k) log("probe", `${name}  (${k.type.name})`);
  }
  for (const name of CFG.enumerate) {
    const k = getClass(name);
    if (!k) continue;
    log("enum", `=== ${k.type.name} ===`);
    for (const f of k.fields)
      log("enum", `  field  ${f.type.name}  ${f.name}`);
    for (const m of k.methods) {
      const p = m.parameters.map((x: any) => x.type.name).join(", ");
      log("enum", `  method ${m.returnType.name}  ${m.name}(${p})`);
    }
  }
}

function audio() {
  const cls = getClass("AudioSource");
  if (!cls) return;
  const all = Il2Cpp.gc.choose(cls);
  let spatial = 0, flat = 0;
  const dists: number[] = [];
  for (const s of all.slice(0, CFG.audioCap)) {
    const blend = tryGet(() => (s.method("get_spatialBlend") as any).invoke());
    if (blend === null) continue;
    if (blend > 0) {
      spatial++;
      const d = tryGet(() => (s.method("get_maxDistance") as any).invoke());
      if (d !== null) dists.push(d);
    } else flat++;
  }
  log("audio", `total=${all.length} spatial=${spatial} flat=${flat}`);
  if (dists.length) {
    dists.sort((a, b) => a - b);
    log("audio", `  maxDistance min=${dists[0]} med=${dists[dists.length >> 1]} max=${dists.at(-1)}`);
  }
}

function photon() {
  const pn = getClass("PhotonNetwork");
  if (!pn) return;
  const state = tryGet(() => (pn.method("get_connectionStateDetailed") as any).invoke());
  const inRoom = tryGet(() => (pn.method("get_InRoom") as any).invoke());
  log("photon", `state=${state}  InRoom=${inRoom}`);
  if (!inRoom) return;
  const room = tryGet(() => (pn.method("get_CurrentRoom") as any).invoke());
  if (room?.handle && !room.handle.isNull()) {
    const r = new Il2Cpp.Object(room.handle);
    const name = tryGet(() => (r.method("get_Name") as any).invoke().toString());
    const pc = tryGet(() => (r.method("get_PlayerCount") as any).invoke());
    const max = tryGet(() => (r.method("get_MaxPlayers") as any).invoke());
    log("photon", `room="${name}" players=${pc}/${max}`);
  }
  log("photon", `IsMasterClient=${tryGet(() => (pn.method("get_IsMasterClient") as any).invoke())}`);
}

let rpcCount = 0;
function traceRpcs() {
  const pn = getClass("PhotonNetwork");
  if (!pn) return;
  const overloads = pn.methods.filter((m: any) => m.name === "RaiseEvent");
  for (const m of overloads)
    Interceptor.attach(m.virtualAddress, {
      onEnter(args) {
        if (rpcCount++ >= CFG.rpcCap) return;
        const code = args[0].toInt32() & 0xff;
        log("rpc", `RaiseEvent code=0x${code.toString(16).padStart(2, "0")}`);
      },
    });
  log("rpc", `traced ${overloads.length} RaiseEvent overload(s)`);
}

function moderationProbe() {
  const hits: Il2Cpp.Class[] = [];
  for (const a of Il2Cpp.domain.assemblies)
    for (const k of a.image.classes) {
      const n = k.namespace || "";
      if (n.startsWith("System") || n.startsWith("Unity") || n.startsWith("Mono.")) continue;
      if (/Block|Moderation|Mute/.test(k.name)) hits.push(k);
    }
  log("mod", `${hits.length} candidate classes`);
  for (const k of hits.slice(0, 30)) {
    const fs = k.fields.filter((f: any) => /Block|Mute|Ignor|Hide/i.test(f.name));
    if (!fs.length) continue;
    log("mod", `${k.namespace || ""}.${k.name}:`);
    for (const f of fs) log("mod", `  ${f.type.name}  ${f.name}`);
  }
}

function traceAudioSpawn() {
  const cls = getClass("AudioSource");
  if (!cls) return;
  for (const name of ["Play", "PlayOneShot"]) {
    const m = cls.tryMethod(name);
    if (!m) continue;
    Interceptor.attach(m.virtualAddress, {
      onEnter(args) {
        const inst = new Il2Cpp.Object(args[0]);
        const blend = tryGet(() => (inst.method("get_spatialBlend") as any).invoke());
        if (blend > 0) {
          const d = tryGet(() => (inst.method("get_maxDistance") as any).invoke());
          log("spawn", `${name}  blend=${blend}  maxDistance=${d}`);
        }
      },
    });
  }
}

Il2Cpp.perform(() => {
  log("main", "il2cpp ready");
  const ns = inventory();
  fingerprints(ns);
  probes();
  audio();
  photon();
  moderationProbe();
  traceRpcs();
  traceAudioSpawn();
  setInterval(() => Il2Cpp.perform(() => { audio(); photon(); }), CFG.tickMs);
  log("main", "monitoring");
});
