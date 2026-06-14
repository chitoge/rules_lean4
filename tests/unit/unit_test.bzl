"""Starlark unit tests for the pure helpers (lakefile parsing, BUILD gen, distribution resolution).
Run with no Lean/cc toolchain."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lean:distributions.bzl", "distribution")

# buildifier: disable=bzl-visibility
load("//lean/private:lakefile.bzl", "gen_build", "glob_roots", "parse_lakefile", "quoted")

_FULL = """name = "importGraph"
defaultTargets = ["ImportGraph", "graph"]

# a comment

[[require]]
name = "Cli"
scope = "leanprover"

[leanOptions]
experimental.module = true

[[lean_lib]]
name = "ImportGraph"

[[lean_lib]]
name = "ImportGraphTest"
globs = ["ImportGraphTest.+"]
"""

def _parse_basic(ctx):
    env = unittest.begin(ctx)
    cfg = parse_lakefile("name = \"Cli\"\ndefaultTargets = [\"Cli\"]\n[[lean_lib]]\nname = \"Cli\"\n")
    asserts.equals(env, "Cli", cfg.name)
    asserts.equals(env, ["Cli"], cfg.defaults)
    asserts.equals(env, [("Cli", None, None)], cfg.libs)
    asserts.equals(env, {}, cfg.opts)
    asserts.equals(env, [], cfg.requires)
    return unittest.end(env)

def _parse_full(ctx):
    env = unittest.begin(ctx)
    cfg = parse_lakefile(_FULL)
    asserts.equals(env, "importGraph", cfg.name)
    asserts.equals(env, ["ImportGraph", "graph"], cfg.defaults)
    asserts.equals(env, ["Cli"], cfg.requires)
    asserts.equals(env, {"experimental.module": "true"}, cfg.opts)
    asserts.equals(env, ["ImportGraph", "ImportGraphTest"], [name for name, _, _ in cfg.libs])
    asserts.equals(env, "[\"ImportGraphTest.+\"]", cfg.libs[1][1])
    return unittest.end(env)

def _parse_srcdir(ctx):
    env = unittest.begin(ctx)
    cfg = parse_lakefile("[[lean_lib]]\nname = \"Foo\"\nsrcDir = \"src\"\n")
    asserts.equals(env, [("Foo", None, "src")], cfg.libs)
    return unittest.end(env)

def _glob_roots_cases(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ["Cli"], glob_roots("Cli", None))
    asserts.equals(env, ["CliTest"], glob_roots("CliTest", "[\"CliTest.+\"]"))
    asserts.equals(env, ["A", "B"], glob_roots("X", "[\"A.*\", \"B\"]"))
    return unittest.end(env)

def _quoted_cases(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ["A", "B"], quoted("[\"A\", \"B\"]"))
    asserts.equals(env, [], quoted("[]"))
    return unittest.end(env)

def _gen_build_alias(ctx):
    env = unittest.begin(ctx)

    # lib name != package name -> alias to the default lib + require wired
    b = gen_build(struct(name = "importGraph", libs = [("ImportGraph", None, None)], opts = {}, requires = ["Cli"], defaults = ["ImportGraph", "graph"]))
    asserts.true(env, "alias(name = \"importGraph\", actual = \"ImportGraph\")" in b, "alias for differing name")
    asserts.true(env, "@lean_pkg_Cli//:Cli" in b, "require edge wired")
    asserts.true(env, "allow_empty = True" in b, "globs are allow_empty")

    # lib name == package name -> no alias
    asserts.false(env, "alias(" in gen_build(struct(name = "Cli", libs = [("Cli", None, None)], opts = {}, requires = [], defaults = ["Cli"])), "no alias when names match")
    return unittest.end(env)

def _gen_build_multi_require(ctx):
    # A package requiring several others wires an edge to each (transitive resolution).
    env = unittest.begin(ctx)
    b = gen_build(struct(name = "P", libs = [("P", None, None)], opts = {}, requires = ["A", "B"], defaults = ["P"]))
    asserts.true(env, "@lean_pkg_A//:A" in b, "first require wired")
    asserts.true(env, "@lean_pkg_B//:B" in b, "second require wired")
    return unittest.end(env)

def _distribution_cases(ctx):
    env = unittest.begin(ctx)
    urls, sha, strip = distribution("4.30.0", "linux-x86_64")
    asserts.equals(env, ["https://github.com/leanprover/lean4/releases/download/v4.30.0/lean-4.30.0-linux.tar.zst"], urls)
    asserts.equals(env, "lean-4.30.0-linux", strip)
    asserts.equals(env, 64, len(sha))

    urls2, _, strip2 = distribution("4.30.0", "darwin-aarch64")
    asserts.true(env, urls2[0].endswith("lean-4.30.0-darwin_aarch64.tar.zst"), "darwin arm url")
    asserts.equals(env, "lean-4.30.0-darwin_aarch64", strip2)
    return unittest.end(env)

_parse_basic_test = unittest.make(_parse_basic)
_parse_full_test = unittest.make(_parse_full)
_parse_srcdir_test = unittest.make(_parse_srcdir)
_glob_roots_test = unittest.make(_glob_roots_cases)
_quoted_test = unittest.make(_quoted_cases)
_gen_build_alias_test = unittest.make(_gen_build_alias)
_gen_build_multi_require_test = unittest.make(_gen_build_multi_require)
_distribution_test = unittest.make(_distribution_cases)

def unit_test_suite(name):
    unittest.suite(
        name,
        _parse_basic_test,
        _parse_full_test,
        _parse_srcdir_test,
        _glob_roots_test,
        _quoted_test,
        _gen_build_alias_test,
        _gen_build_multi_require_test,
        _distribution_test,
    )
