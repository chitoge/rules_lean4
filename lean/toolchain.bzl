"""The Lean toolchain: LeanToolchainInfo + the `lean_toolchain` rule.

Every field needed to run `lean`/`leanc` hermetically (under a sandbox or remote worker) is here;
`all_files` is attached to every action's inputs so the toolchain is fully declared.
"""

LeanToolchainInfo = provider(
    doc = "Resolved Lean toolchain tools, env, and the full input file set.",
    fields = {
        "lean": "File: bin/lean launcher (dlopens libleanshared.so)",
        "leanc": "File: bin/leanc — C compile + runtime link driver",
        "lake": "File: bin/lake (optional)",
        "sysroot": "str: toolchain root, exported as LEAN_SYSROOT (relocatable)",
        "std_olean_root": "str: lib/lean — stdlib LEAN_PATH entry",
        "lib_dirs": "depset[str]: LD_LIBRARY_PATH entries (lib/lean, lib)",
        "all_files": "depset[File]: every toolchain file — declared as action inputs",
        "include_dir": "str: the include/ dir holding lean.h (an FFI include path)",
        "cc_hdrs": "depset[File]: the include/ headers (FFI compilation inputs)",
    },
)

def _parent(p):
    return p.rsplit("/", 1)[0]

def _lean_toolchain_impl(ctx):
    # Derive every env path from the actual staged File path (bin/lean lives at <sysroot>/bin/lean),
    # so the paths stay correct after RBE path-mapping rewrites prefixes.
    lean = ctx.file.lean
    sysroot = _parent(_parent(lean.path))  # <sysroot>/bin/lean -> <sysroot>
    std_olean_root = sysroot + "/lib/lean"
    leaninfo = LeanToolchainInfo(
        lean = lean,
        leanc = ctx.file.leanc,
        lake = ctx.file.lake,
        sysroot = sysroot,
        std_olean_root = std_olean_root,
        lib_dirs = depset([std_olean_root, sysroot + "/lib"]),
        all_files = depset(ctx.files.tools + ctx.files.std_oleans + ctx.files.libs),
        include_dir = sysroot + "/include",
        cc_hdrs = depset(ctx.files.cc_hdrs),
    )
    return [platform_common.ToolchainInfo(leaninfo = leaninfo)]

lean_toolchain = rule(
    implementation = _lean_toolchain_impl,
    doc = "Gathers an extracted Lean release into a resolvable toolchain.",
    attrs = {
        # Plain files (not `executable` targets) — we hand the File to ctx.actions.run(executable=...).
        "lean": attr.label(allow_single_file = True, mandatory = True),
        "leanc": attr.label(allow_single_file = True, mandatory = True),
        "lake": attr.label(allow_single_file = True),
        "tools": attr.label_list(allow_files = True, doc = "bin/ (clang, ld.lld, ...) + include/"),
        "std_oleans": attr.label_list(allow_files = True, doc = "lib/lean stdlib oleans + runtime libs"),
        "libs": attr.label_list(allow_files = True, doc = "lib/ (libc++, glibc, libLLVM, ...)"),
        "cc_hdrs": attr.label_list(allow_files = True, doc = "include/ headers (lean.h) for FFI."),
    },
)
