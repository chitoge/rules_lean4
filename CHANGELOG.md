# Changelog

All notable changes to `rules_lean4` are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## 0.2.0 — 2026-06-18

- Default Lean toolchain is now **4.31.0** (4.30.0 remains checksum-pinned and selectable). Because
  Lean has no cross-version source/olean compatibility, the example dependencies were bumped to
  their 4.31 releases: import-graph `v4.31.0`, lean4-cli `v4.31.0`, Leancremental `v0.4.2`.
- **Fix:** a `lean_binary`/`lean_test`/`lean_library` could fail to import a module from a `deps`
  target when the two shared a top-level module namespace (e.g. a target with `Foo.App` depending on
  a library that provides `Foo.Core`), with `object file '...olean' of module Foo.Core does not
  exist`. Lean binds a top-level namespace to a single search root, so dependency oleans under a
  *contested* namespace are now merged into one root during elaboration (disjoint roots, such as a
  mathlib import, stay on `LEAN_PATH` uncopied). Splitting a library into smaller targets under one
  namespace now works. Covered by `tests/lib_dep`.
- **New: `lean_lake_cache`** repository rule — ingest a mathlib-scale library's prebuilt olean cache
  the way Lake users do: clone the project, download the Lean release it pins, run `lake exe cache
  get`, and expose the consolidated oleans via `lean_import`. See [`examples/mathlib`](examples/mathlib),
  a separate module that machine-checks a proof against mathlib. It also takes `sub_dir` (the Lake
  project's subdirectory) and `build_targets` (Lake libraries to build *from source* on top of the
  fetched cache) for ingesting a source library that sits on a cached dependency stack.
- Added the `4.30.0-rc2` Lean release to the distribution table (checksum-pinned, selectable) for
  projects that pin a prerelease.
- **Fix:** rules_lean4 no longer registers a Lean toolchain as a normal dependency — its own
  selection (for its tests) is now a `dev_dependency`. The toolchain version is the consumer's single
  choice in their root `MODULE.bazel`; previously rules_lean4's pin leaked into consumers and could
  override theirs, producing `incompatible header` olean errors when they pinned a different release.
- The root module now registers **no Lean toolchain at all**. The toolchain-using tests moved to a
  separate consumer workspace, [`integration/`](integration), run as a nested Bazel via the
  `//:integration_test` target (`rules_bazel_integration_test`). The root keeps only the pure-Starlark
  `tests/unit` suite + API docs. Canonical command: `bazel test //... //:integration_test`.

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
