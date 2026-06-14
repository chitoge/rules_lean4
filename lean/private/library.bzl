"""lean_library: compile a set of `.lean` modules (and optional C/C++ FFI) to a library."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//lean:providers.bzl", "LeanInfo", "merge_lean_info")
load(":actions.bzl", "cc_deps_objects", "compile_ffi", "elaborate")

_TOOLCHAIN = "@rules_lean4//lean:toolchain_type"

# FFI inputs shared by the FFI-capable rules. Two ways to bring native code, neither of which makes
# a Lean rule depend on a C++ toolchain:
#   * ffi_srcs  — C compiled with the Lean toolchain's bundled clang (zero-config, hermetic, C only).
#   * cc_deps   — objects from cc_library targets you compiled with your own cc toolchain (C or C++).
FFI_ATTRS = {
    "ffi_srcs": attr.label_list(allow_files = [".c"], doc = "C sources compiled with Lean's bundled clang."),
    "ffi_hdrs": attr.label_list(allow_files = [".h"], doc = "Headers for ffi_srcs."),
    "includes": attr.string_list(doc = "-I include dirs for ffi_srcs."),
    "copts": attr.string_list(doc = "Extra flags for the bundled FFI compile."),
    "cc_deps": attr.label_list(providers = [CcInfo], doc = "cc_library deps whose objects are linked in."),
}

def src_root(ctx):
    """The import root as it appears in source File paths (exec-root-relative).

    Includes the repo's workspace_root so module names are correct for sources in external repos
    (e.g. fetched Lake dependencies), where ctx.label.package is empty at the repo root.
    """
    parts = []
    if ctx.label.workspace_root:
        parts.append(ctx.label.workspace_root)
    if ctx.label.package:
        parts.append(ctx.label.package)
    if ctx.attr.src_root and ctx.attr.src_root != ".":
        parts.append(ctx.attr.src_root)
    return "/".join(parts) or "."

def ffi_objects(ctx, tc):
    """Objects from this target's ffi_srcs (bundled) + cc_deps (CcInfo)."""
    objects = []
    if ctx.files.ffi_srcs:
        objects += compile_ffi(ctx, ctx.files.ffi_srcs, ctx.files.ffi_hdrs, ctx.attr.includes, ctx.attr.copts, tc)
    if ctx.attr.cc_deps:
        objects += cc_deps_objects(ctx.attr.cc_deps)
    return objects

def _lean_library_impl(ctx):
    tc = ctx.toolchains[_TOOLCHAIN].leaninfo
    dep = merge_lean_info(ctx.attr.deps)
    oleans, objects = elaborate(ctx, ctx.label.name, ctx.files.srcs, src_root(ctx), dep, tc, ctx.attr.opts)
    direct_objects = [objects] + ffi_objects(ctx, tc)

    return [
        DefaultInfo(files = depset([oleans] + direct_objects)),
        LeanInfo(
            transitive_oleans = depset([oleans], transitive = [dep.transitive_oleans]),
            transitive_olean_roots = depset([oleans.path], transitive = [dep.transitive_olean_roots]),
            transitive_srcs = depset(ctx.files.srcs, transitive = [dep.transitive_srcs]),
            transitive_objects = depset(direct_objects, transitive = [dep.transitive_objects]),
        ),
    ]

COMMON_ATTRS = dict(
    FFI_ATTRS,
    deps = attr.label_list(providers = [LeanInfo], doc = "Other lean_library/lean_import deps."),
    src_root = attr.string(default = ".", doc = "Import root; Foo/Bar.lean => module Foo.Bar."),
    opts = attr.string_dict(doc = "Lean options, passed as -Dkey=value (e.g. experimental.module=true)."),
    _builder = attr.label(default = "//lean/private:elaborate.lean", allow_single_file = True),
)

lean_library = rule(
    implementation = _lean_library_impl,
    doc = "Compiles `.lean` modules (and optional FFI) to oleans + native objects.",
    attrs = dict(COMMON_ATTRS, srcs = attr.label_list(allow_files = [".lean"], mandatory = True, doc = "`.lean` source modules to compile.")),
    toolchains = [_TOOLCHAIN],
)
