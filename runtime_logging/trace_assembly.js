// trace_assembly.js — spam-trace every method in an Il2Cpp assembly. Change
// the assembly name to whatever you're investigating. Noisy — pipe to a file.

Il2Cpp.perform(() => {
    console.log("[*] Starting Il2Cpp.trace() on PhotonRealtime assembly");

    Il2Cpp.trace()
        .assemblies(Il2Cpp.domain.assembly("PhotonRealtime"))
        .and()
        .attach();
});