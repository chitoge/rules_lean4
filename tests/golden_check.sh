#!/usr/bin/env bash
# Runs a binary and asserts its stdout contains an expected substring.
# Usage: golden_check.sh <binary> <expected-substring>
set -euo pipefail
out="$("$1")"
if ! grep -qF -- "$2" <<<"$out"; then
  echo "stdout of $1 did not contain '$2'; got: $out" >&2
  exit 1
fi
