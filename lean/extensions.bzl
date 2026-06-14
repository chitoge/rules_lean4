"""The `lean` module extension: the standard bzlmod toolchain-extension pattern, for Lean.

A single `lean.toolchain(...)` tag declares the toolchain; the impl instantiates one download repo
per supported platform (lazily fetched — only the selected platform's tarball is downloaded) plus a
hub repo that registers a `toolchain()` for each, with exec/target constraints. Users name a
version; the extension resolves the per-platform URLs and checksums.

The toolchain is always a pinned, checksummed download — no host/elan dependency — so builds are
hermetic and identical across machines (incl. RBE). Two ways to point it:
  * by version (default): `lean.toolchain(version = "4.30.0")` — per-platform release tarballs.
  * custom URL:           `lean.toolchain(version, urls = {...}, sha256 = {...})`.
"""

load(":distributions.bzl", "PLATFORMS", "distribution")
load(":repositories.bzl", "lean_download_toolchain_repository")

_toolchain_tag = tag_class(attrs = {
    "version": attr.string(default = "4.30.0", doc = "Lean version; should match //:lean-toolchain."),
    "urls": attr.string_list_dict(doc = "Optional per-platform URL override (platform -> [urls])."),
    "sha256": attr.string_dict(doc = "Optional per-platform sha256 override."),
    "strip_prefix": attr.string_dict(doc = "Optional per-platform strip_prefix override."),
})

def _hub_impl(rctx):
    lines = ['package(default_visibility = ["//visibility:public"])\n']
    for plat, repo in rctx.attr.platform_repos.items():
        ec = ", ".join(['"%s"' % c for c in PLATFORMS[plat][1]])
        lines.append("""toolchain(
    name = "{name}",
    exec_compatible_with = [{ec}],
    target_compatible_with = [{ec}],
    toolchain = "@{repo}//:lean_toolchain",
    toolchain_type = "@rules_lean4//lean:toolchain_type",
)""".format(name = plat, ec = ec, repo = repo))
    rctx.file("BUILD.bazel", "\n".join(lines))

_lean_toolchains_hub = repository_rule(
    implementation = _hub_impl,
    attrs = {"platform_repos": attr.string_dict(mandatory = True)},
)

def _lean_impl(mctx):
    # Last-write-wins across the dep graph (root module's tags come last → take precedence).
    version = "4.30.0"
    urls_override = {}
    sha_override = {}
    strip_override = {}
    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            version = tag.version
            urls_override = tag.urls
            sha_override = tag.sha256
            strip_override = tag.strip_prefix

    platform_repos = {}
    for plat in PLATFORMS:
        urls, sha, strip = distribution(version, plat)
        if plat in urls_override:
            urls = urls_override[plat]
        if plat in sha_override:
            sha = sha_override[plat]
        if plat in strip_override:
            strip = strip_override[plat]
        repo = "lean_%s_%s" % (version.replace(".", "_"), plat.replace("-", "_"))
        lean_download_toolchain_repository(
            name = repo,
            urls = urls,
            sha256 = sha,
            strip_prefix = strip,
        )
        platform_repos[plat] = repo

    _lean_toolchains_hub(name = "lean_toolchains", platform_repos = platform_repos)

    # Non-reproducible: record resolved URLs+hashes into MODULE.bazel.lock.
    return mctx.extension_metadata(reproducible = False)

lean = module_extension(
    implementation = _lean_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    os_dependent = False,
    arch_dependent = False,
)
