// hook_patterns.js — the main instrumentation methods used in the paper.
//
// Methods:
//   (i)   Modify arguments before the original runs
//   (ii)  Modify the return value
//   (iii) Read or write fields on the calling instance (`this`)
//   (iv)  Override the method's logic entirely (skip original / replace return)
//
// To use against a target: discover the managed class + method name via the
// runtime logger or Il2CppDumper output and fill in the descriptor.

'use strict';

function onIl2CppReady(cb) {
    if (typeof Il2Cpp === "undefined" || !Il2Cpp.isInitialized) {
        setTimeout(function () { onIl2CppReady(cb); }, 100);
    } else {
        cb();
    }
}

function resolveManagedMethod(desc) {
    const asm = Il2Cpp.domain.assembly(desc.assemblyName);
    const img = asm.image;
    const klass = img.class(desc.fullClassName);
    if (desc.argumentCount === undefined) {
        return klass.method(desc.methodName);
    }
    return klass.method(desc.methodName, desc.argumentCount);
}


// (i) Modify arguments before the original function runs.
function hookModifyArgs(desc, mutateArgs) {
    onIl2CppReady(function () {
        const method = resolveManagedMethod(desc);
        console.log("[*] hookModifyArgs on", method.fullName);

        Interceptor.attach(method.virtualAddress, {
            onEnter(args) {
                try { mutateArgs(this, args); }
                catch (e) { console.log("[!] mutateArgs error:", e); }
            }
        });
    });
}


// (ii) Change the return value before the caller uses it.
function hookModifyReturn(desc, mutateRet) {
    onIl2CppReady(function () {
        const method = resolveManagedMethod(desc);
        console.log("[*] hookModifyReturn on", method.fullName);

        Interceptor.attach(method.virtualAddress, {
            onLeave(retval) {
                try {
                    const newVal = mutateRet(this, retval);
                    if (newVal !== undefined) retval.replace(newVal);
                } catch (e) { console.log("[!] mutateRet error:", e); }
            }
        });
    });
}


// (iii) Read or write fields of the calling object (`this`).
function hookAccessFields(desc, access) {
    onIl2CppReady(function () {
        const method = resolveManagedMethod(desc);
        console.log("[*] hookAccessFields on", method.fullName);

        Interceptor.attach(method.virtualAddress, {
            onEnter(args) {
                const instancePtr = args[0]; // 'this' for instance methods
                try { access(this, instancePtr); }
                catch (e) { console.log("[!] access error:", e); }
            }
        });
    });
}


// (iv) Override logic (skip original or force a fixed result).
function hookOverrideLogic(desc, decide) {
    onIl2CppReady(function () {
        const method = resolveManagedMethod(desc);
        console.log("[*] hookOverrideLogic on", method.fullName);

        Interceptor.attach(method.virtualAddress, {
            onEnter(args) {
                this.skipOriginal = false;
                this.altRetval = undefined;
                try { decide.call(this, args); }
                catch (e) { console.log("[!] decide error:", e); }
            },
            onLeave(retval) {
                if (this.altRetval !== undefined) retval.replace(this.altRetval);
            }
        });
    });
}


rpc.exports = {
    hookmodifyargs: hookModifyArgs,
    hookmodifyreturn: hookModifyReturn,
    hookaccessfields: hookAccessFields,
    hookoverridelogic: hookOverrideLogic
};
