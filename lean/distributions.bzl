"""Known Lean release distributions: version -> platform -> (url, sha256, strip_prefix).

The default URL/checksum table for the official leanprover/lean4 GitHub releases. Users can override
any platform's `urls`, `sha256`, or `strip_prefix` per-platform on the `lean.toolchain` tag (e.g. to
point at an internal mirror or a version not listed here).

Asset naming follows leanprover/lean4 GitHub releases:
  linux  x86_64 : lean-<v>-linux.tar.zst
  linux  aarch64: lean-<v>-linux_aarch64.tar.zst
  darwin x86_64 : lean-<v>-darwin.tar.zst
  darwin aarch64: lean-<v>-darwin_aarch64.tar.zst
Each tarball extracts under a single top dir `lean-<v>-<suffix>/` (strip_prefix).
"""

# platform key -> (asset suffix, bazel constraint values)
PLATFORMS = {
    "linux-x86_64": ("linux", ["@platforms//os:linux", "@platforms//cpu:x86_64"]),
    "linux-aarch64": ("linux_aarch64", ["@platforms//os:linux", "@platforms//cpu:aarch64"]),
    "darwin-x86_64": ("darwin", ["@platforms//os:osx", "@platforms//cpu:x86_64"]),
    "darwin-aarch64": ("darwin_aarch64", ["@platforms//os:osx", "@platforms//cpu:aarch64"]),
}

_BASE = "https://github.com/leanprover/lean4/releases/download"

# version -> platform -> sha256 ("" = unverified; recorded into MODULE.bazel.lock on first fetch).
_SHA256 = {
    "4.30.0": {
        "linux-x86_64": "4dad74141c2c119ca1aa626656be83b8e14238afba97271fd7bf1eb3f081b319",
        "linux-aarch64": "c99c6f0edd446956d4758c59d4383e8e6411ff6cc71a01f9caabe5eba454121d",
        "darwin-x86_64": "b38dd8a25b5b5096c6c9019e7ffaddbd91a23fcb5382753225e3314515768ca2",
        "darwin-aarch64": "072dca4a38fbc0d3cedb96fea886cc243b424f2bd16247596200b9a9ab93f0f5",
    },
    "4.31.0": {
        "linux-x86_64": "07a633cc8d9151cbc08825ea4cdda50d4b02a2c9cb852c0131b13046f49cad7f",
        "linux-aarch64": "b1bf1d3c586b76cf4a86212a595d8b9edd99f438a41cce85d5780fa9347c811b",
        "darwin-x86_64": "6dac7a8f9d6d0bc339b4ea9376c06a88f3fd1a7f462beb3c7ded9fbc934f3fb5",
        "darwin-aarch64": "264105500c8abdf37b68ffe03390a783ed259807807222698da8dd92d6ce0a27",
    },
}

def distribution(version, platform, extra = None):
    """Return (urls, sha256, strip_prefix) for a version+platform, honoring `extra` overrides."""
    if extra and version in extra and platform in extra[version]:
        d = extra[version][platform]
        return ([d["url"]], d.get("sha256", ""), d.get("strip_prefix", ""))
    if platform not in PLATFORMS:
        fail("unsupported Lean platform %r (known: %s)" % (platform, ", ".join(PLATFORMS.keys())))
    suffix = PLATFORMS[platform][0]
    url = "{base}/v{v}/lean-{v}-{s}.tar.zst".format(base = _BASE, v = version, s = suffix)
    sha = _SHA256.get(version, {}).get(platform, "")
    strip = "lean-{v}-{s}".format(v = version, s = suffix)
    return ([url], sha, strip)
