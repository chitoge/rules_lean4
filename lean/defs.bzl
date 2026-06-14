"""Public API for rules_lean4.

    load("@rules_lean4//lean:defs.bzl",
         "lean_library", "lean_binary", "lean_test",
         "lean_cc_binary", "lean_cc_test", "lean_cc_headers", "lean_import")
"""

load("//lean:providers.bzl", _LeanInfo = "LeanInfo")
load("//lean/private:binary.bzl", _lean_binary = "lean_binary", _lean_test = "lean_test")
load("//lean/private:cc_binary.bzl", _lean_cc_binary = "lean_cc_binary", _lean_cc_test = "lean_cc_test")
load("//lean/private:cc_headers.bzl", _lean_cc_headers = "lean_cc_headers")
load("//lean/private:import.bzl", _lean_import = "lean_import")
load("//lean/private:library.bzl", _lean_library = "lean_library")

lean_library = _lean_library
lean_binary = _lean_binary
lean_test = _lean_test
lean_cc_binary = _lean_cc_binary
lean_cc_test = _lean_cc_test
lean_cc_headers = _lean_cc_headers
lean_import = _lean_import
LeanInfo = _LeanInfo
