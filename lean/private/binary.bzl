"""lean_binary / lean_test: elaborate a target's modules, gather FFI objects, and link an exe."""

load("//lean:providers.bzl", "merge_lean_info")
load(":actions.bzl", "elaborate", "link")
load(":library.bzl", "COMMON_ATTRS", "ffi_objects", "src_root")

_TOOLCHAIN = "@rules_lean4//lean:toolchain_type"

def _lean_binary_impl(ctx):
    tc = ctx.toolchains[_TOOLCHAIN].leaninfo
    dep = merge_lean_info(ctx.attr.deps)

    # Elaborate + codegen this target's own modules (a distinct subdir so the oleans/objects trees
    # don't collide with the `<name>` executable output).
    _oleans, own_objects = elaborate(ctx, ctx.label.name + ".obj", ctx.files.srcs, src_root(ctx), dep, tc, ctx.attr.opts)

    objects = [own_objects] + dep.transitive_objects.to_list() + ffi_objects(ctx, tc)
    exe = ctx.actions.declare_file(ctx.label.name)
    link(ctx, exe, objects, tc)
    return [DefaultInfo(executable = exe, runfiles = ctx.runfiles(files = [exe]))]

_BINARY_ATTRS = dict(
    COMMON_ATTRS,
    srcs = attr.label_list(allow_files = [".lean"], mandatory = True, doc = "`.lean` source modules (one defines `main`)."),
    _linker = attr.label(default = "//lean/private:link.lean", allow_single_file = True),
)

lean_binary = rule(
    implementation = _lean_binary_impl,
    doc = "Builds a static native executable from Lean modules (+ optional FFI).",
    executable = True,
    attrs = _BINARY_ATTRS,
    toolchains = [_TOOLCHAIN],
)

lean_test = rule(
    implementation = _lean_binary_impl,
    doc = "Like lean_binary, run as a test (the program's exit code is the verdict).",
    test = True,
    attrs = _BINARY_ATTRS,
    toolchains = [_TOOLCHAIN],
)
