#!/bin/sh
# Runs each conformance test directory named on the command line (bare
# names under test/conformance/, e.g. "lexer-vocabulary"), invoking its
# test.sh, and prints a pass/fail summary. Exit status is nonzero if any
# named test failed (or doesn't exist). Used by GNUmakefile's per-category
# test-* targets - see GNUmakefile for how fixtures are grouped by which
# part of poc they exercise (lexer/parser/semantic/modules/layout/llvm).
#
# Deliberately does not stop at the first failure: every named test runs,
# so a single invocation (e.g. plain "make test") reports the full
# picture in one pass rather than stopping at the first failing category.

set -u
cd "$(dirname "$0")/conformance" || exit 1

pass=0
fail=0
failed=""

for name in "$@"; do
  if [ ! -f "$name/test.sh" ]; then
    echo "run-tests.sh: no such test: $name" >&2
    fail=$((fail + 1))
    failed="$failed $name"
    continue
  fi
  if (cd "$name" && sh test.sh); then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed="$failed $name"
  fi
done

echo
echo "$pass passed, $fail failed"
if [ -n "$failed" ]; then
  echo "failed:$failed"
  exit 1
fi
