"""Parse a `lakefile.toml` (line-based; no TOML library in Starlark) and generate a BUILD file with
a `lean_library` per `[[lean_lib]]`. Kept separate from deps.bzl so the pure functions are unit-testable.
"""

def quoted(v):
    """The quoted strings in a TOML value like `["A", "B"]` (odd-index split segments)."""
    segs = v.split("\"")
    return [segs[i] for i in range(1, len(segs), 2)]

def parse_lakefile(content):
    """Parse the lean_libs, leanOptions, requires, package name and defaultTargets from a lakefile."""
    libs = []  # (name, globs_raw, srcDir)
    opts = {}  # [leanOptions]
    requires = []  # [[require]] names
    pkg_name = ""
    default_targets = []
    section = "root"
    name, globs, srcdir = None, None, None
    for raw in content.split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            if section == "lean_lib" and name:
                libs.append((name, globs, srcdir))
            name, globs, srcdir = None, None, None
            section = "lean_lib" if line == "[[lean_lib]]" else "require" if line == "[[require]]" else "leanOptions" if line == "[leanOptions]" else "other"
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if section == "root":
            if k == "name":
                pkg_name = v.strip("\"")
            elif k == "defaultTargets":
                default_targets = quoted(v)
        elif section == "lean_lib":
            if k == "name":
                name = v.strip("\"")
            elif k == "globs":
                globs = v
            elif k == "srcDir":
                srcdir = v.strip("\"")
        elif section == "require" and k == "name":
            requires.append(v.strip("\""))
        elif section == "leanOptions":
            opts[k] = v.strip("\"")
    if section == "lean_lib" and name:
        libs.append((name, globs, srcdir))
    return struct(libs = libs, opts = opts, requires = requires, name = pkg_name, defaults = default_targets)

def glob_roots(name, globs):
    """A lean_lib's roots: the lib name, or the modules named by `globs = ["X.+", ...]`."""
    if not globs:
        return [name]
    roots = []
    for g in quoted(globs):
        if g.endswith(".+") or g.endswith(".*"):
            g = g[:-2]
        if g:
            roots.append(g)
    return roots or [name]

def gen_build(cfg):
    """Generate a BUILD with a lean_library per lib, plus a package-name alias to the default lib."""
    opts_str = ", ".join(["\"%s\": \"%s\"" % (k, v) for k, v in cfg.opts.items()])
    deps_str = ", ".join(["\"@lean_pkg_%s//:%s\"" % (r, r) for r in cfg.requires])
    lib_names = [name for name, _, _ in cfg.libs]
    out = [
        "load(\"@rules_lean4//lean:defs.bzl\", \"lean_library\")",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]
    for name, globs, srcdir in cfg.libs:
        patterns = []
        for r in glob_roots(name, globs):
            rp = r.replace(".", "/")
            patterns += ["\"%s.lean\"" % rp, "\"%s/**/*.lean\"" % rp]
        out.append("lean_library(")
        out.append("    name = \"%s\"," % name)
        out.append("    srcs = glob([%s], allow_empty = True)," % ", ".join(patterns))
        if srcdir and srcdir != ".":
            out.append("    src_root = \"%s\"," % srcdir)
        if opts_str:
            out.append("    opts = {%s}," % opts_str)
        if deps_str:
            out.append("    deps = [%s]," % deps_str)
        out.append(")")
        out.append("")

    # Expose the package name as an alias to its default library, so `require`rs can depend on
    # `@lean_pkg_<name>//:<name>` even when the library name differs (e.g. importGraph -> ImportGraph).
    main_lib = ([t for t in cfg.defaults if t in lib_names] or lib_names or [""])[0]
    if cfg.name and main_lib and cfg.name not in lib_names:
        out += ["alias(name = \"%s\", actual = \"%s\")" % (cfg.name, main_lib), ""]
    return "\n".join(out)
