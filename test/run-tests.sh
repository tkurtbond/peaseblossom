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
#
# Fixtures run several at once, as many as the host has processors, or
# -j <n>, or TEST_JOBS: each works only in its own directory. Each one's
# output is kept and printed in the order named, once all have run. With
# one job they run in turn and print as they go.
#
#   test/run-tests.sh [-j <n>] <name>...

set -u
jobs=${TEST_JOBS:-}
if [ "${1:-}" = -j ]; then
  jobs=${2:?run-tests.sh: -j needs a number}
  shift 2
fi
if [ -z "$jobs" ]; then
  # getconf on Linux, FreeBSD and NetBSD; OpenBSD's lacks the name
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpuonline 2>/dev/null || echo 1)
fi
cd "$(dirname "$0")/conformance" || exit 1

pass=0
fail=0
failed=""

# count NAME STATUS: adds NAME's outcome to the summary
count() {
  if [ "$2" = 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed="$failed $1"
  fi
}

names=
for name in "$@"; do
  if [ ! -f "$name/test.sh" ]; then
    echo "run-tests.sh: no such test: $name" >&2
    count "$name" 1
  else
    names="$names $name"
  fi
done

if [ "$jobs" -le 1 ]; then
  for name in $names; do
    (cd "$name" && sh test.sh)
    count "$name" $?
  done
else
  out=$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX") || exit 1
  trap 'rm -rf "$out"' EXIT
  trap 'exit 130' INT TERM
  # Each fixture's output in <out>/<name>.out, its exit status in .status
  printf '%s\n' $names | xargs -n 1 -P "$jobs" sh -c \
    '(cd "$1" && sh test.sh) >"$0/$1.out" 2>&1 </dev/null; echo $? >"$0/$1.status"' "$out"
  for name in $names; do
    cat "$out/$name.out"
    count "$name" "$(cat "$out/$name.status" 2>/dev/null || echo 1)"
  done
fi

echo
echo "$pass passed, $fail failed"
if [ -n "$failed" ]; then
  echo "failed:$failed"
  exit 1
fi
