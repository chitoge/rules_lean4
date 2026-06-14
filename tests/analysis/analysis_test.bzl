"""Analysis-phase tests: LeanInfo propagation/dedup, action mnemonics, and an expected failure."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//lean:defs.bzl", "LeanInfo")

def _propagation(ctx):
    # libTop -> {libLeft, libRight} -> libBase. transitive_oleans should accumulate all four, with
    # libBase deduped (reached via both left and right) — i.e. exactly 4, not 5.
    env = analysistest.begin(ctx)
    info = analysistest.target_under_test(env)[LeanInfo]
    asserts.equals(env, 4, len(info.transitive_oleans.to_list()))
    asserts.equals(env, 4, len(info.transitive_olean_roots.to_list()))
    return analysistest.end(env)

def _binary_actions(ctx):
    env = analysistest.begin(ctx)
    mnemonics = [a.mnemonic for a in analysistest.target_actions(env)]
    asserts.true(env, "LeanElab" in mnemonics, "binary elaborates")
    asserts.true(env, "LeanLink" in mnemonics, "binary links")
    return analysistest.end(env)

def _ffi_action(ctx):
    env = analysistest.begin(ctx)
    mnemonics = [a.mnemonic for a in analysistest.target_actions(env)]
    asserts.true(env, "LeanCC" in mnemonics, "ffi_srcs compiled with bundled clang")
    return analysistest.end(env)

def _bad_deps(ctx):
    # A non-LeanInfo target in `deps` must fail analysis (the providers = [LeanInfo] constraint).
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "mandatory provider")
    return analysistest.end(env)

propagation_test = analysistest.make(_propagation)
binary_actions_test = analysistest.make(_binary_actions)
ffi_action_test = analysistest.make(_ffi_action)
bad_deps_test = analysistest.make(_bad_deps, expect_failure = True)
