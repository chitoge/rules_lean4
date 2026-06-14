"""lean_import — ingest a prebuilt olean tree (e.g. a mathlib cache) as a LeanInfo.

No compile action: the practical way to depend on mathlib without recompiling thousands of modules.
The LEAN_PATH root is derived from the target's location (workspace_root + package + import_dir), so
it is correct for oleans living in an external repo (e.g. a downloaded archive).
"""

load("//lean:providers.bzl", "LeanInfo")

def _lean_import_impl(ctx):
    parts = []
    if ctx.label.workspace_root:
        parts.append(ctx.label.workspace_root)
    if ctx.label.package:
        parts.append(ctx.label.package)
    if ctx.attr.import_dir and ctx.attr.import_dir != ".":
        parts.append(ctx.attr.import_dir)
    olean_root = "/".join(parts) or "."

    oleans = depset(ctx.files.oleans)
    return [
        DefaultInfo(files = oleans),
        LeanInfo(
            transitive_oleans = oleans,
            transitive_olean_roots = depset([olean_root]),
            transitive_srcs = depset(ctx.files.srcs),
            transitive_objects = depset(ctx.files.objects),
        ),
    ]

lean_import = rule(
    implementation = _lean_import_impl,
    doc = "Wrap prebuilt .olean (and optional .o) artifacts as a Lean dependency.",
    attrs = {
        "oleans": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Prebuilt olean artifacts. Accepts the full per-module set: `.olean` and " +
                  "(module system) `.olean.private`, `.olean.server`, `.ir` — all are staged on " +
                  "LEAN_PATH for importers.",
        ),
        "import_dir": attr.string(default = ".", doc = "Dir (under the package) that is the LEAN_PATH root."),
        "srcs": attr.label_list(allow_files = [".lean"], doc = "Optional `.lean` sources, exposed via LeanInfo for tooling."),
        "objects": attr.label_list(allow_files = [".o"], doc = "Optional precompiled `.o` objects to link into downstream binaries."),
    },
)
