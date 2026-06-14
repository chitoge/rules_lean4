"""lean_cc_headers: expose the Lean toolchain's C headers (lean.h, ...) as a CcInfo.

Depend a `cc_library` on this so your FFI C/C++ can `#include <lean/lean.h>` while being compiled
with your own cc toolchain.
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_TOOLCHAIN = "@rules_lean4//lean:toolchain_type"

def _lean_cc_headers_impl(ctx):
    tc = ctx.toolchains[_TOOLCHAIN].leaninfo
    compilation_context = cc_common.create_compilation_context(
        headers = tc.cc_hdrs,
        includes = depset([tc.include_dir]),
    )
    return [CcInfo(compilation_context = compilation_context)]

lean_cc_headers = rule(
    implementation = _lean_cc_headers_impl,
    doc = "Provides the Lean toolchain's headers (lean.h) as a CcInfo for cc_library FFI.",
    toolchains = [_TOOLCHAIN],
)
