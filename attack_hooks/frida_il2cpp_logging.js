// frida_il2cpp_logging.js — install a enter/leave log on a managed
// method by class + method name. Useful for tracing a single method without
// pulling in the full runtime logger.

function onIl2CppReady(cb) {
    if (typeof Il2Cpp === "undefined" || !Il2Cpp.isInitialized) {
        setTimeout(function () { onIl2CppReady(cb); }, 100);
    } else {
        cb();
    }
}


function installLoggingHook(fullClassName, methodName) {
    onIl2CppReady(function () {
        let found = false;

        Il2Cpp.domain.assemblies.forEach(assembly => {
            if (found) return;
            const klass = assembly.image.tryClass(fullClassName);
            if (!klass) return;
            const method = klass.tryMethod(methodName);
            if (!method) return;

            found = true;
            console.log("[*] Logging hook on", method.fullName,
                        "in assembly", assembly.name);

            const originalImpl = method.implementation;
            method.implementation = function () {
                console.log("[+] Enter:", method.fullName);
                const result = originalImpl.apply(this, arguments);
                console.log("[-] Leave:", method.fullName);
                return result;
            };
        });

        if (!found) {
            console.log("[!]", fullClassName + "." + methodName,
                        "not found in any loaded assembly.");
        }
    });
}


rpc.exports = {
    installlogginghook: installLoggingHook
};
