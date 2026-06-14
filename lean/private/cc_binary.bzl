"""lean_cc_binary / lean_cc_test: a C/C++ program that links a Lean library (reverse FFI).

The C/C++ `main` (which calls Lean code exported with `@[export]`) lives in a `cc_library` that you
compile with your own cc toolchain; this rule just links its objects together with the Lean
library's via leanc, so the Lean runtime resolves. No cpp toolchain is declared here — bring the
Lean headers into your cc_library via `@rules_lean4//lean:headers`.
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//lean:providers.bzl", "LeanInfo", "merge_lean_info")
load(":actions.bzl", "cc_deps_objects", "link")

_TOOLCHAIN = "@rules_lean4//lean:toolchain_type"

def _lean_cc_binary_impl(ctx):
    tc = ctx.toolchains[_TOOLCHAIN].leaninfo
    dep = merge_lean_info(ctx.attr.deps)

    objects = cc_deps_objects(ctx.attr.cc_deps) + dep.transitive_objects.to_list()
    exe = ctx.actions.declare_file(ctx.label.name)
    link(ctx, exe, objects, tc)
    return [DefaultInfo(executable = exe, runfiles = ctx.runfiles(files = [exe]))]

_ATTRS = {
    "cc_deps": attr.label_list(
        providers = [CcInfo],
        mandatory = True,
        doc = "cc_library targets (including the one with `main`) to link.",
    ),
    "deps": attr.label_list(providers = [LeanInfo], doc = "lean_library targets to link (and call)."),
    "_linker": attr.label(default = "//lean/private:link.lean", allow_single_file = True),
}

lean_cc_binary = rule(
    implementation = _lean_cc_binary_impl,
    doc = "A C/C++ executable that links and calls a Lean library (reverse FFI).",
    executable = True,
    attrs = _ATTRS,
    toolchains = [_TOOLCHAIN],
)

lean_cc_test = rule(
    implementation = _lean_cc_binary_impl,
    doc = "Like lean_cc_binary, run as a test.",
    test = True,
    attrs = _ATTRS,
    toolchains = [_TOOLCHAIN],
)
