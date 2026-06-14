"""Loading external Lean dependencies. Three entry points, from most to least automatic:

* `lake` extension — read a whole `lake-manifest.json`, fetch every git package at its pinned rev,
  and generate a `lean_library` for each by parsing its `lakefile.toml`:

      lake = use_extension("@rules_lean4//lean:deps.bzl", "lake")
      lake.from_manifest(manifest = "//:lake-manifest.json", sha256 = {"Cli": "..."})
      use_repo(lake, "lean_pkg_Cli", ...)   # one repo per package, named lean_pkg_<Name>

  Depend on a package as `@lean_pkg_<Name>//:<Name>` (a package-name alias to its default library)
  or `@lean_pkg_<Name>//:<Lib>`. The manifest lists the full transitive set and each package's
  `[[require]]`s are wired up, so transitive deps resolve automatically. Scope: git packages with a
  parseable `lakefile.toml`.

* `lean_git` extension — add a single package straight from a git tag/commit and build it from
  source. The fetch is delegated to Bazel's `new_git_repository`; you declare the module `roots`, so
  it needs no lakefile parsing and works for `lakefile.lean` packages too.

* `lean_olean_archive` repo rule — ingest a package's prebuilt `.olean` cache instead of building
  it (the practical option for mathlib-scale deps).
"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("//lean/private:lakefile.bzl", "gen_build", "parse_lakefile")

# --- repository rule: fetch a package + generate its BUILD ---

def _lean_lake_package_impl(rctx):
    rctx.download_and_extract(
        url = rctx.attr.urls,
        sha256 = rctx.attr.sha256,
        stripPrefix = rctx.attr.strip_prefix,
    )
    sub = rctx.attr.sub_dir
    config = (sub + "/lakefile.toml") if sub else "lakefile.toml"
    build = (sub + "/BUILD.bazel") if sub else "BUILD.bazel"
    if not rctx.path(config).exists:
        fail(("package %r has no %s (likely a programmatic lakefile.lean). Convert it with " +
              "`lake translate-config toml` and vendor the result, or ingest prebuilt oleans via " +
              "lean_olean_archive.") % (rctx.name, config))
    rctx.file(build, gen_build(parse_lakefile(rctx.read(config))))

lean_lake_package = repository_rule(
    implementation = _lean_lake_package_impl,
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(),
        "strip_prefix": attr.string(default = ""),
        "sub_dir": attr.string(doc = "Package subdirectory within the repo (manifest `subDir`)."),
    },
)

# --- module extension: lake-manifest.json -> one package repo each ---

def _lake_impl(mctx):
    packages = {}
    sha256 = {}
    for mod in mctx.modules:
        for tag in mod.tags.from_manifest:
            manifest = json.decode(mctx.read(mctx.path(tag.manifest)))
            for p in manifest.get("packages", []):
                if p.get("type") == "git":
                    packages[p["name"]] = p
            sha256.update(tag.sha256)

    for name, p in packages.items():
        url = p["url"]
        rev = p["rev"]
        repo = url.rsplit("/", 1)[-1]
        lean_lake_package(
            name = "lean_pkg_" + name,
            urls = [url + "/archive/" + rev + ".tar.gz"],
            sha256 = sha256.get(name, ""),
            strip_prefix = repo + "-" + rev,
            sub_dir = p.get("subDir") or "",
        )

    return mctx.extension_metadata(reproducible = False)

lake = module_extension(
    implementation = _lake_impl,
    tag_classes = {
        "from_manifest": tag_class(attrs = {
            "manifest": attr.label(mandatory = True, doc = "A lake-manifest.json to load deps from."),
            "sha256": attr.string_dict(doc = "Optional package name -> archive sha256 (else unverified)."),
        }),
    },
)

# --- prebuilt-olean ingestion (for mathlib-scale deps) ---

# A repo created by `use_repo_rule` inherits the *calling* module's repo mapping, in which this
# module may be named something other than `rules_lean4` (a consumer can rename it via `repo_name`).
# So the generated BUILD loads our rules through the canonical label, which resolves regardless.
_DEFS_BZL = str(Label("//lean:defs.bzl"))

_OLEAN_BUILD = """\
load("{defs}", "lean_import")
package(default_visibility = ["//visibility:public"])

lean_import(
    name = "{name}",
    oleans = glob(
        [
            "{root}**/*.olean",
            "{root}**/*.olean.private",
            "{root}**/*.olean.server",
            "{root}**/*.ir",
        ],
        # Plain (non-module-system) caches have only .olean; the other patterns then match nothing.
        allow_empty = True,
    ),
    import_dir = "{import_dir}",
)
"""

def _lean_olean_archive_impl(rctx):
    rctx.download_and_extract(url = rctx.attr.urls, sha256 = rctx.attr.sha256, stripPrefix = rctx.attr.strip_prefix)
    d = rctx.attr.import_dir
    rctx.file("BUILD.bazel", _OLEAN_BUILD.format(
        defs = _DEFS_BZL,
        name = rctx.attr.lib_name,
        root = (d + "/") if d and d != "." else "",
        import_dir = d,
    ))

lean_olean_archive = repository_rule(
    implementation = _lean_olean_archive_impl,
    doc = "Download an archive of prebuilt `.olean` files and expose it via lean_import (e.g. a " +
          "mathlib cache packed with `lake pack`). See docs in lean_import.",
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(),
        "strip_prefix": attr.string(default = ""),
        "import_dir": attr.string(default = ".", doc = "Dir within the archive that is the LEAN_PATH root."),
        "lib_name": attr.string(default = "oleans"),
    },
)

# --- single git package by tag/commit (built from source; no lakefile parsing) ---
#
# The actual fetch is delegated to Bazel's own `new_git_repository`; this extension only computes the
# repo name and generates the `lean_library` BUILD it builds. The git ref (tag/commit) is the
# integrity anchor, so no checksum is needed — pin a `commit` for full reproducibility (tags are
# mutable). It needs no lakefile parsing — you declare the library's module `roots` — so it also
# works for packages that ship a programmatic `lakefile.lean`.

_GIT_BUILD = """\
load("@rules_lean4//lean:defs.bzl", "lean_library")
package(default_visibility = ["//visibility:public"])

lean_library(
    name = "{name}",
    srcs = glob([{patterns}], allow_empty = True),{deps}{opts}
)
"""

def _git_glob_patterns(roots):
    pats = []
    for r in roots:
        rp = r.replace(".", "/")
        pats += ["\"%s.lean\"" % rp, "\"%s/**/*.lean\"" % rp]
    return ", ".join(pats)

def _git_build_file(tag, repo):
    lib = tag.lib_name or repo
    roots = tag.roots or [lib]
    deps = ""
    if tag.deps:
        deps = "\n    deps = [%s]," % ", ".join(["\"%s\"" % d for d in tag.deps])
    opts = ""
    if tag.opts:
        opts = "\n    opts = {%s}," % ", ".join(["\"%s\": \"%s\"" % (k, v) for k, v in tag.opts.items()])
    return _GIT_BUILD.format(name = lib, patterns = _git_glob_patterns(roots), deps = deps, opts = opts)

def _git_repo_impl(mctx):
    for mod in mctx.modules:
        for tag in mod.tags.repository:
            if bool(tag.tag) == bool(tag.commit):
                fail("lean_git.repository(name = %r): set exactly one of `tag` or `commit`." % tag.name)
            base = tag.remote[:-1] if tag.remote.endswith("/") else tag.remote
            repo = base.rsplit("/", 1)[-1]
            if repo.endswith(".git"):
                repo = repo[:-4]
            ref = {"commit": tag.commit} if tag.commit else {"tag": tag.tag}
            new_git_repository(
                name = tag.name,
                remote = tag.remote,
                build_file_content = tag.build_file_content or _git_build_file(tag, repo),
                **ref
            )
    return mctx.extension_metadata(reproducible = False)

lean_git = module_extension(
    implementation = _git_repo_impl,
    tag_classes = {
        "repository": tag_class(
            doc = "Fetch a Lean package from git (via Bazel's new_git_repository) at a tag/commit " +
                  "and build it from source as a lean_library. Depend on it as `@<name>//:<lib_name>`.",
            attrs = {
                "name": attr.string(mandatory = True, doc = "Repository name (use_repo + `@<name>//...`)."),
                "remote": attr.string(mandatory = True, doc = "Git repo URL, e.g. https://github.com/owner/repo."),
                "tag": attr.string(doc = "Tag to fetch (e.g. v0.3.0). Set exactly one of `tag` / `commit`."),
                "commit": attr.string(doc = "Commit SHA to fetch (most reproducible). Set exactly one of `tag` / `commit`."),
                "lib_name": attr.string(doc = "Generated lean_library target name (default: the repo name)."),
                "roots": attr.string_list(doc = "Module roots to glob as sources (default: [lib_name]); " +
                                                "Foo.Bar globs Foo/Bar.lean + Foo/Bar/**/*.lean."),
                "deps": attr.string_list(doc = "Labels for the generated library's deps (other lean_* targets)."),
                "opts": attr.string_dict(doc = "Lean options for the generated library (e.g. experimental.module=true)."),
                "build_file_content": attr.string(doc = "Full BUILD content override; bypasses source globbing."),
            },
        ),
    },
)
