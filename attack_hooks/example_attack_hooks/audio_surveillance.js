// Audio surveillance example (I1) — defeat spatial-audio falloff.
//
// Goal: hear remote voice at full volume regardless of distance between
// avatars.
//
// Pattern: hook a lifecycle method on the per-remote-player voice playback
// object (typically called when the playback prefab is set up or when its
// rolloff is configured). After the original runs, walk to the Unity
// AudioSource field on the playback object and override its spatial
// parameters. Optionally also hook the AudioSource setters as a safety net
// to block the app from re-applying its spatial config later.
//
// Pattern A from hook_patterns.js (arg-rewrite at Interceptor.attach, with
// the override happening at onLeave on the AudioSource setters).
//
// Per-app discovery: run the runtime logger's class probe to find the
// per-remote-player playback prefab class (typically holds an `audioSource`
// field of type UnityEngine.AudioSource and an identifying field like an
// actor / player ID). Identify the lifecycle methods on that class — these
// vary per app but commonly include a "configure rolloff" method, an
// "initialize 3D audio" method, or a generic "Setup" method called once
// when a remote user's voice prefab is created. Fill in CONFIG.

'use strict';

const CONFIG = {
  PLAYBACK_PREFAB_CLASS:  '<PLAYBACK_PREFAB_CLASS>',
  LIFECYCLE_METHODS:      ['<LIFECYCLE_METHOD_1>', '<LIFECYCLE_METHOD_2>'],
  AUDIO_SOURCE_FIELD:     'audioSource',

  // null = don't override
  FORCE_MAX_DISTANCE:     5000.0,
  FORCE_MIN_DISTANCE:     null,
  FORCE_SPATIAL_BLEND:    null,    // 0.0 = pure 2D, fully defeats falloff

  LOG_LIMIT:              200,
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

function asObject(value) {
  if (value === null || value === undefined) return null;
  try { if (value instanceof Il2Cpp.Object) return value; } catch (_) {}
  try {
    const h = value.handle !== undefined ? value.handle : value;
    if (h && !h.isNull()) return new Il2Cpp.Object(h);
  } catch (_) {}
  return null;
}

function readField(obj, name) {
  try { return obj.field(name).value; } catch { return null; }
}

function callNumber(obj, methodName) {
  try { return Number(obj.method(methodName, 0).invoke()); } catch { return null; }
}

function setOnAudioSource(audioSource, setter, value) {
  try { audioSource.method(setter, 1).invoke(value); return true; }
  catch { return false; }
}


function overrideAudioSource(prefab, reason) {
  const audioSource = asObject(readField(prefab, CONFIG.AUDIO_SOURCE_FIELD));
  if (!audioSource) return;

  const beforeMax   = callNumber(audioSource, 'get_maxDistance');
  const beforeBlend = callNumber(audioSource, 'get_spatialBlend');

  if (typeof CONFIG.FORCE_MAX_DISTANCE  === 'number') setOnAudioSource(audioSource, 'set_maxDistance',  CONFIG.FORCE_MAX_DISTANCE);
  if (typeof CONFIG.FORCE_MIN_DISTANCE  === 'number') setOnAudioSource(audioSource, 'set_minDistance',  CONFIG.FORCE_MIN_DISTANCE);
  if (typeof CONFIG.FORCE_SPATIAL_BLEND === 'number') setOnAudioSource(audioSource, 'set_spatialBlend', CONFIG.FORCE_SPATIAL_BLEND);

  const afterMax   = callNumber(audioSource, 'get_maxDistance');
  const afterBlend = callNumber(audioSource, 'get_spatialBlend');

  logLine(
    `[audio-surv] ${reason} ` +
    `maxDistance=${beforeMax}->${afterMax} ` +
    `spatialBlend=${beforeBlend}->${afterBlend}`
  );
}


Il2Cpp.perform(() => {
  const found = findClass(CONFIG.PLAYBACK_PREFAB_CLASS);
  if (!found) {
    logLine(`[audio-surv] class not loaded: ${CONFIG.PLAYBACK_PREFAB_CLASS}`);
    return;
  }

  for (const methodName of CONFIG.LIFECYCLE_METHODS) {
    const method = found.klass.tryMethod(methodName);
    if (!method) {
      logLine(`[audio-surv] method not found: ${methodName}`);
      continue;
    }
    const addr = safeMethodAddr(method);
    if (!addr) continue;

    Interceptor.attach(addr, {
      onEnter(args) { this.prefab = new Il2Cpp.Object(args[0]); },
      onLeave()     { overrideAudioSource(this.prefab, methodName); },
    });
    logLine(`[audio-surv] attached ${methodName}`);
  }
});
