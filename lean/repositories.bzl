"""Repository rule: fetch + extract a hermetic Lean release tarball and write its BUILD.

`lean_download_toolchain_repository` is the only toolchain source — a pinned, checksummed release
(no host/elan dependency, so builds are reproducible and identical across machines). It only
downloads, extracts, and writes a BUILD file — no compilation, no host-tool symlinks — so it is
remote-execution-safe.
"""

# sysroot / LEAN_PATH / LD_LIBRARY_PATH are derived from staged File paths inside the rule impl, so
# no exec-root prefix is hardcoded here (keeps RBE path-mapping consistent).
_BUILD = """\
load("@rules_lean4//lean:toolchain.bzl", "lean_toolchain")

package(default_visibility = ["//visibility:public"])

lean_toolchain(
    name = "lean_toolchain",
    lean = "bin/lean",
    leanc = "bin/leanc",
    lake = "bin/lake",
    tools = glob(["bin/**", "include/**"]),
    std_oleans = glob(["lib/lean/**"]),
    libs = glob(["lib/**"], exclude = ["lib/lean/**"]),
    cc_hdrs = glob(["include/**"]),
)
"""

def _download_impl(rctx):
    rctx.download_and_extract(
        url = rctx.attr.urls,
        sha256 = rctx.attr.sha256,  # "" = unverified (recorded into MODULE.bazel.lock on fetch)
        stripPrefix = rctx.attr.strip_prefix,
    )
    rctx.file("BUILD.bazel", _BUILD)

lean_download_toolchain_repository = repository_rule(
    implementation = _download_impl,
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(),
        "strip_prefix": attr.string(default = ""),
    },
)
