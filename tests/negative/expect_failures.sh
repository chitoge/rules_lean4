#!/usr/bin/env bash
# Asserts that each //tests/negative target FAILS to build (they exercise error paths: a false
# proof, a missing import, an undefined @[extern]). Extra args are passed to `bazel build`.
# Usage: tests/negative/expect_failures.sh [bazel flags...]
set -u

targets=(bad_proof missing_import undefined_extern)
rc=0
for t in "${targets[@]}"; do
  if bazel build "//tests/negative:${t}" "$@" >/dev/null 2>&1; then
    echo "FAIL: //tests/negative:${t} built but was expected to fail"
    rc=1
  else
    echo "ok: //tests/negative:${t} failed to build as expected"
  fi
done
exit "${rc}"
