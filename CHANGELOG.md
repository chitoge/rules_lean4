# Changelog

All notable changes to `rules_lean4` are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## Unreleased

- Default Lean toolchain is now **4.31.0** (4.30.0 remains checksum-pinned and selectable). Because
  Lean has no cross-version source/olean compatibility, the example dependencies were bumped to
  their 4.31 releases: import-graph `v4.31.0`, lean4-cli `v4.31.0`, Leancremental `v0.4.2`.

## 0.1.0

Initial release.

- Hermetic, checksum-pinned Lean toolchain via the `lean` module extension (download-only; no host
  or elan dependency), selected per execution platform so remote execution works the standard way.
- Core rules: `lean_library`, `lean_binary`, `lean_test`.
- Forward FFI (Lean → C/C++): `ffi_srcs` (Lean's bundled clang) and `cc_deps` (your own cc
  toolchain), plus `lean_cc_headers` (`//lean:headers`) to expose `lean.h` to a `cc_library`.
- Reverse FFI (C/C++ → Lean): `lean_cc_binary`, `lean_cc_test`.
- Prebuilt-olean ingestion: `lean_import` and the `lean_olean_archive` repository rule (for
  mathlib-scale dependencies).
- External Lake dependencies: the `lake` module extension generates targets from a
  `lake-manifest.json`, resolving transitive `lakefile.toml` requires.
- Single-package git dependencies: the `lean_git` module extension fetches a library from a git
  tag/commit (via Bazel's `new_git_repository`) and builds it from source, with no lakefile parsing
  (so it handles `lakefile.lean` packages too).
- Supported platforms: Linux x86_64 / aarch64 (verified), macOS x86_64 / aarch64 (best-effort).
