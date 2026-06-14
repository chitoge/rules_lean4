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
lean.toolchain(version = "4.30.0")   # match your //:lean-toolchain
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
    tag = "v0.3.0",
    # roots = ["Leancremental"],  # defaults to [lib_name]; lib_name defaults to the repo name
)
use_repo(lean_git, "leancremental")
```
```starlark
# BUILD.bazel
lean_binary(name = "app", srcs = ["Main.lean"], deps = ["@leancremental//:Leancremental"])
```

This is exercised end-to-end by [`tests/git_dep`](tests/git_dep), which fetches
[Leancremental](https://github.com/chitoge/Leancremental) at `v0.3.0` and runs that library's README
quick example.

### Large libraries (mathlib): prebuilt oleans

Building mathlib from source is impractical, so ingest its prebuilt `.olean` cache instead of
compiling it. `lean_olean_archive` downloads an archive of oleans and exposes it via `lean_import`
(no compilation); point it at oleans produced by `lake exe cache get` + `lake pack`:

```starlark
# MODULE.bazel
archive = use_repo_rule("@rules_lean4//lean:deps.bzl", "lean_olean_archive")
archive(name = "mathlib_oleans", urls = ["https://.../mathlib-oleans.tar.zst"], sha256 = "...")
```

Then depend on `@mathlib_oleans//:oleans`. (`lean_import` also takes loose `.olean` targets directly.)

## Examples / tests

`bazel test //...` runs the full suite under [`tests/`](tests):

- **Examples** (runnable, self-asserting): building an executable ([`exe`](tests/exe)), machine-checked
  proofs ([`proof`](tests/proof)), forward FFI via both `ffi_srcs` and `cc_deps` ([`ffi`](tests/ffi)),
  reverse FFI with C++ ([`reverse_ffi`](tests/reverse_ffi)), a transitive external Lake dependency
  ([`dep`](tests/dep)), a `lakefile.toml` package loaded via the `lake` extension
  ([`lake_toml`](tests/lake_toml)), a library fetched from a git tag ([`git_dep`](tests/git_dep)),
  and a diamond intra-package import graph ([`multi`](tests/multi)).
- **Unit** ([`unit`](tests/unit)): pure-Starlark tests of the lakefile parser, BUILD generation, and
  distribution resolver (no toolchain).
- **Analysis** ([`analysis`](tests/analysis)): provider propagation/dedup, action mnemonics, and an
  expected-failure case.
- **Negative** ([`negative`](tests/negative)): targets that must *fail* to build (a false proof, a
  missing import, an undefined `@[extern]`); asserted by `expect_failures.sh` in CI.

CI also runs the suite under `--spawn_strategy=sandboxed` (input-completeness), checks build
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
tests/                # examples + unit / analysis / negative tests
e2e/                  # separate module that consumes rules_lean4 as a renamed external dep
docs/                 # stardoc API-doc target
```
