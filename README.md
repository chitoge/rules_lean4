# rules_lean4

Bazel (bzlmod) rules for building [Lean 4](https://lean-lang.org) projects with a **hermetic,
checksummed toolchain** and full **remote-execution / caching** support.

The Lean toolchain is downloaded and pinned by checksum (never the host's `lean`/elan install), so
builds are reproducible and identical across machines. The toolchain ships its own `clang`, `ld.lld`,
libc++, glibc, and the compiled stdlib, so C compilation and linking need nothing from the host.

## Setup

Requires **Bazel ≥ 9.0** (bzlmod; the rules load `CcInfo`/`cc_common` from `rules_cc`, which moved
out of Bazel's globals in 9.x) and a `WORKSPACE`-less, bzlmod-only project.

```starlark
# MODULE.bazel
bazel_dep(name = "rules_lean4", version = "0.1.0")

lean = use_extension("@rules_lean4//lean:extensions.bzl", "lean")
lean.toolchain(version = "4.31.0")   # match your //:lean-toolchain
use_repo(lean, "lean_toolchains")
register_toolchains("@lean_toolchains//:all")
```

**Pure-Lean targets need no C toolchain at all** — no Lean rule depends on a cpp toolchain. A C/C++
toolchain is only needed for the FFI paths that use one (the `cc_deps` / `lean_cc_*` examples register
[`toolchains_llvm`](https://github.com/bazel-contrib/toolchains_llvm) for a hermetic clang/clang++).

## Rules

```starlark
load("@rules_lean4//lean:defs.bzl",
     "lean_library", "lean_binary", "lean_test",
     "lean_cc_binary", "lean_cc_test", "lean_cc_headers", "lean_import")
```

| Symbol           | Purpose                                                                   |
|------------------|---------------------------------------------------------------------------|
| `lean_library`   | Compile `.lean` modules (+ optional FFI) to oleans/objects.               |
| `lean_binary`    | Build a static native executable from Lean modules.                       |
| `lean_test`      | A `lean_binary` run as a test (the program's exit code is the verdict).   |
| `lean_cc_binary` | A C/C++ program that links and calls a Lean library (reverse FFI).        |
| `lean_cc_test`   | A `lean_cc_binary` run as a test.                                         |
| `lean_cc_headers`| Lean's C headers (`lean.h`) as a `CcInfo`, for `cc_library` FFI.          |
| `lean_import`    | Wrap prebuilt `.olean` trees (e.g. a mathlib cache) as a dependency.      |

```starlark
# BUILD.bazel
load("@rules_lean4//lean:defs.bzl", "lean_binary", "lean_library")

lean_library(name = "mylib", srcs = ["MyLib/Basic.lean"])
lean_binary(name = "app", srcs = ["Main.lean"], deps = [":mylib"])
```

### FFI (Lean → C/C++)

`@[extern "sym"]` in Lean calls the C function `sym`. Bring the native code in two ways:

- **`ffi_srcs`** — C compiled with the **Lean toolchain's own clang**. Zero-config, hermetic, needs no
  cc toolchain — but C only (the bundle has no C++ stdlib headers).
- **`cc_deps`** — a `cc_library` you compile with **your own cc toolchain** (C or C++); Lean links its
  objects. Use `@rules_lean4//lean:headers` so the `cc_library` finds `lean.h`.

### Reverse FFI (C/C++ → Lean)

`lean_cc_binary`/`lean_cc_test` link a `cc_library` containing `main` (which calls `@[export]`ed Lean
functions) against a Lean library. The C/C++ is compiled by your cc toolchain; Lean links it:

```starlark
load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_lean4//lean:defs.bzl", "lean_cc_binary", "lean_library")

lean_library(name = "mylib", srcs = ["MyLib.lean"])  # has @[export] functions
cc_library(name = "main", srcs = ["main.cpp"], deps = ["@rules_lean4//lean:headers"])
lean_cc_binary(name = "app", cc_deps = [":main"], deps = [":mylib"])
```

Linking always uses the Lean toolchain, so the Lean runtime resolves.

## External Lake dependencies

The `lake` module extension reads a `lake-manifest.json`, fetches each git package at its pinned
rev, and generates a `lean_library` for it (from the package's `lakefile.toml`, including its
`leanOptions`). Depend on a package as `@lean_pkg_<Name>//:<Lib>`:

```starlark
# MODULE.bazel
lake = use_extension("@rules_lean4//lean:deps.bzl", "lake")
lake.from_manifest(manifest = "//:lake-manifest.json")
use_repo(lake, "lean_pkg_Cli")
```
```starlark
# BUILD.bazel
lean_binary(name = "app", srcs = ["Main.lean"], deps = ["@lean_pkg_Cli//:Cli"])
```

The manifest lists the full transitive set and each package's `[[require]]`s are wired up, so
transitive dependencies resolve automatically. This covers git packages with a parseable
`lakefile.toml`.

### From a git tag (any package, including `lakefile.lean`)

To add a single library straight from a git tag or commit, use the `lean_git` extension. The fetch
is delegated to Bazel's own `new_git_repository`, and you declare the library's module `roots`, so
it needs no lakefile parsing — it works even for packages with a programmatic `lakefile.lean`. The
git ref is the integrity anchor (no checksum to compute); pin a `commit` for full reproducibility,
since tags are mutable.

```starlark
# MODULE.bazel
lean_git = use_extension("@rules_lean4//lean:deps.bzl", "lean_git")
lean_git.repository(
    name = "leancremental",
    remote = "https://github.com/chitoge/Leancremental",
    tag = "v0.4.2",
    # roots = ["Leancremental"],  # defaults to [lib_name]; lib_name defaults to the repo name
)
use_repo(lean_git, "leancremental")
```
```starlark
# BUILD.bazel
lean_binary(name = "app", srcs = ["Main.lean"], deps = ["@leancremental//:Leancremental"])
```

This is exercised end-to-end by [`tests/git_dep`](tests/git_dep), which fetches
[Leancremental](https://github.com/chitoge/Leancremental) at `v0.4.2` and runs that library's README
quick example.

### Large libraries (mathlib): prebuilt oleans

Building mathlib from source is impractical, so ingest its prebuilt `.olean` cache instead of
compiling it. Two ways:

**`lean_lake_cache`** (ergonomic) clones a Lake project at a tag/commit, downloads the Lean release
it pins, runs `lake exe cache get` to fetch the prebuilt oleans for the project *and its transitive
deps*, and exposes the consolidated result via `lean_import`:

```starlark
# MODULE.bazel
mathlib = use_repo_rule("@rules_lean4//lean:deps.bzl", "lean_lake_cache")
mathlib(
    name = "mathlib",
    remote = "https://github.com/leanprover-community/mathlib4",
    tag = "v4.31.0",      # must match your toolchain version; or pin `commit = "..."`
    lib_name = "Mathlib",
)
```

Then depend on `@mathlib//:Mathlib`. It needs `git` + network at fetch time and GNU coreutils, and
the cache is several GB — so keep mathlib-backed targets in a separate module (see
[`examples/mathlib`](examples/mathlib)), not your default `//...` suite. This is exercised by that
example, which machine-checks a proof (infinitude of primes, `ring`/`nlinarith`) against mathlib.

`lean_lake_cache` also takes `sub_dir` (the Lake project's subdirectory in the repo) and
`build_targets` (Lake libraries to build *from source* after the cache is fetched — their deps come
prebuilt, their oleans are included too). Together these ingest a source library that sits on top of
mathlib: [`examples/aeneas`](examples/aeneas) builds [Aeneas](https://github.com/AeneasVerif/aeneas)'s
Lean backend (`build_targets = ["Aeneas", "AeneasMeta"]`, `sub_dir = "backends/lean"`) on a cached
mathlib, so Aeneas-generated Lean (Rust verified in Lean) can be checked with `lean_library`.

**`lean_olean_archive`** (manual) downloads a single olean tarball you host yourself (e.g. from
`lake exe cache get` + `lake pack`) and exposes it via `lean_import`:

```starlark
# MODULE.bazel
archive = use_repo_rule("@rules_lean4//lean:deps.bzl", "lean_olean_archive")
archive(name = "mathlib_oleans", urls = ["https://.../mathlib-oleans.tar.zst"], sha256 = "...")
```

Then depend on `@mathlib_oleans//:oleans`. (`lean_import` also takes loose `.olean` targets directly.)

## Examples / tests

This module registers no Lean toolchain (a consumer chooses the version in their root `MODULE.bazel`),
so the root suite is only pure-Starlark **Unit** tests ([`tests/unit`](tests/unit): the lakefile
parser, BUILD generation, and distribution resolver). The toolchain-using tests live in
[`integration/`](integration) — a separate consumer module that selects the toolchain and is run as a
nested Bazel via the `//:integration_test` target. So the canonical commands are:

```sh
bazel test //... //:integration_test   # root unit tests + the nested toolchain suite
# or drive the nested workspace directly:
cd integration && bazel test //...
```

Under [`integration/tests/`](integration/tests):

- **Examples** (runnable, self-asserting): building an executable (`exe`), machine-checked proofs
  (`proof`), forward FFI via both `ffi_srcs` and `cc_deps` (`ffi`), reverse FFI with C++
  (`reverse_ffi`), a transitive external Lake dependency (`dep`), a `lakefile.toml` package loaded via
  the `lake` extension (`lake_toml`), a library fetched from a git tag (`git_dep`), a diamond
  intra-package import graph (`multi`), and a library split into its own target and depended on across
  the target boundary under a shared namespace (`lib_dep`).
- **Analysis** (`analysis`): provider propagation/dedup, action mnemonics, and an expected-failure case.
- **Negative** (`negative`): targets that must *fail* to build (a false proof, a missing import, an
  undefined `@[extern]`); asserted by `expect_failures.sh` in CI.

CI also runs the nested suite under `--spawn_strategy=sandboxed` (input-completeness), checks build
determinism, generates the API docs (`//docs:api`), lints with buildifier, and builds the
[`e2e/`](e2e) module — a separate Bazel module that consumes `rules_lean4` through `bazel_dep` with
the repo deliberately renamed, catching any generated-BUILD or label that assumes the apparent name.

## Remote execution

The toolchain is a per-platform download selected by Bazel's *execution* platform, so RBE works the
standard way: when your workers share the host's architecture (the usual case), no extra config is
needed; for cross-architecture workers, register an execution platform matching them as you would for
any ruleset (`--extra_execution_platforms` / `--host_platform`). FFI via `cc_deps` then also needs a
`cc_toolchain` targeting the worker platform; the bundled `ffi_srcs` path and pure-Lean targets do
not.

## Limitations

This is an early (`0.1.0`) ruleset. Known limitations:

- **Coarse incrementality.** Each `lean_library` elaborates *all* of its modules in a single action,
  so editing one module rebuilds the whole library. Split large libraries into smaller targets to
  recover finer caching.
- **Module system is experimental.** The `module` / `public import` / `meta import` support tracks
  Lean's own `experimental.module` option and may change with upstream Lean.
- **macOS is unverified.** Linux (x86_64, aarch64) is exercised in CI; the macOS job runs but is
  non-gating (the `cc_deps` / reverse-FFI paths depend on the host's clang + SDK resolving).
- **Manifest-based Lake loading is `lakefile.toml`-only.** The `lake` extension parses
  `lakefile.toml`, and the `lake-manifest.json` must be pre-generated by Lake. Packages with a
  programmatic `lakefile.lean` can still be added one at a time with the `lean_git` extension (you
  declare the module roots instead of parsing a lakefile).
- **No from-source build of mathlib-scale libraries.** Ingest their prebuilt `.olean` cache via
  `lean_olean_archive` / `lean_import` instead. CI exercises the `lean_olean_archive` wiring (its
  generated BUILD) in the e2e module; importing a *real* prebuilt cache is validated manually, since
  a committed fixture would pin a binary `.olean` to one toolchain version.
- **No dynamic Lean plugins.** Linking is static via `leanc`; `--load-dynlib`-style shared plugins
  are not supported.
- **Cross-architecture RBE needs a user-supplied execution platform.** Same-arch workers need no
  extra setup (see [Remote execution](#remote-execution)).

## Layout

```
lean/
  defs.bzl            # public API (load everything from here)
  extensions.bzl      # `lean` toolchain module extension
  deps.bzl            # `lake` + `lean_git` extensions, `lean_olean_archive` repo rule
  distributions.bzl   # version -> platform -> (url, sha256)
  repositories.bzl    # download + extract a Lean release
  toolchain.bzl       # lean_toolchain rule + LeanToolchainInfo + toolchain_type
  providers.bzl       # LeanInfo
  private/            # rule implementations + Lean orchestrator scripts
tests/unit/           # pure-Starlark unit tests (the only toolchain-free suite; root module)
integration/          # consumer module: the toolchain-using tests, run via //:integration_test
e2e/                  # separate module that consumes rules_lean4 as a renamed external dep
examples/             # mathlib + Aeneas examples (heavy, separate modules)
docs/                 # stardoc API-doc target
```
