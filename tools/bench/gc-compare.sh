#!/bin/sh
# Compare the collector (rtl/llvm/GarbageCollectedHeap.Mod) of two poc
# checkouts: doc/developer/collector-performance.md has what it measures and the
# results so far.
#
# Usage: tools/bench/gc-compare.sh [-runs n] <old-tree> <new-tree>
#
# Each tree is a checkout of poc (a `git worktree add` of an older commit, or
# this one) with its Stage 1 poc built (tools/bootstrap/stage1, or make
# check). Two workloads, each run n times (default 7) alternating old and new,
# reported as medians of wall time, user time and peak memory, and, where perf
# works (Linux), the instructions and cycles of one more run:
#
#   gcbench   tools/bench/GcBench.mod (new-tree's), built by each tree's
#             Stage 1 poc against that tree's rtl/llvm: binary trees of one
#             node size, then two million blocks of mixed sizes
#   poc-ir    each tree's Stage 1 poc emitting the LLVM IR for old-tree's own
#             source (which both compilers accept), as in the Stage 1 build
#
# Each workload's output must be the same for both trees, or the script
# stops. Run it on a quiet machine: the BSD test VMs running on the same host
# add noise. Needs GNU time (/usr/bin/time -f).
set -e

runs=7
if [ "$1" = -runs ]; then runs=$2; shift 2; fi
if [ $# -ne 2 ]; then
  echo "usage: $0 [-runs n] <old-tree> <new-tree>" >&2; exit 2
fi
old=$(cd "$1" && pwd)
new=$(cd "$2" && pwd)
for tree in "$old" "$new"; do
  if [ ! -x "$tree/build/stage1/bin/poc" ]; then
    echo "$0: no $tree/build/stage1/bin/poc (build Stage 1 there first)" >&2
    exit 1
  fi
done

work=$(mktemp -d "${TMPDIR:-/tmp}/gc-compare.XXXXXX")
trap 'rm -rf "$work"' EXIT

# GcBench, built by each tree's poc against its own runtime
for side in old new; do
  eval tree=\$$side
  mkdir -p "$work/$side/ir"
  cp "$new/tools/bench/GcBench.mod" "$work/$side/"
  (cd "$work/$side" &&
    "$tree/build/stage1/bin/poc" -OC -import-path "$tree/rtl/llvm" \
      -o gcbench -build GcBench.mod >build.log 2>&1) ||
    { cat "$work/$side/build.log" >&2; exit 1; }
done

# run [prefix...] -- workload side: one run of the workload, under the prefix
# command (time, perf stat) if any
run() {
  prefix=""
  while [ "$1" != -- ]; do prefix="$prefix $1"; shift; done
  shift
  eval tree=\$$2
  case $1 in
    gcbench) $prefix "$work/$2/gcbench" >"$work/$2/out" ;;
    poc-ir)
      $prefix "$tree/build/stage1/bin/poc" -OC -import-path "$old/src/front" \
        -import-path "$old/src/back/llvm" -import-path "$old/rtl/llvm" \
        -output-dir "$work/$2/ir" -emit-llvm-ir "$old/src/driver/Poc.Mod" >/dev/null 2>&1
      cat "$work/$2/ir"/*.ll >"$work/$2/out" ;;
  esac
}

median() { # the median of the numbers on stdin
  sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'
}

# Where perf works, one more run counts instructions and cycles. On a hybrid
# CPU (atla's i9-13900HX) each core type has its own counters, and a process
# that moves between them is counted by each in part: so the run is pinned to
# the first performance core and counted there.
perf_prefix=""
events=instructions:u,cycles:u
if [ -r /sys/devices/cpu_core/cpus ]; then
  events=cpu_core/instructions/u,cpu_core/cycles/u
  if command -v taskset >/dev/null 2>&1; then
    perf_prefix="taskset -c $(cut -d- -f1 /sys/devices/cpu_core/cpus | cut -d, -f1)"
  fi
fi
have_perf=no
if command -v perf >/dev/null 2>&1 && perf stat -e $events true >/dev/null 2>&1; then
  have_perf=yes
fi

printf '%-8s %-4s %6s %6s %8s %8s %8s\n' workload tree wall user "peak MB" "instr G" "cycles G"
for w in gcbench poc-ir; do
  run -- $w old; cp "$work/old/out" "$work/expected"
  run -- $w new
  if ! cmp -s "$work/expected" "$work/new/out"; then
    echo "$0: $w's output differs between the trees" >&2; exit 1
  fi
  rm -f "$work/$w.old.times" "$work/$w.new.times"
  i=0
  while [ $i -lt "$runs" ]; do
    for side in old new; do
      run /usr/bin/time -f %e,%U,%M -a -o "$work/$w.$side.times" -- $w $side
    done
    i=$((i + 1))
  done
  for side in old new; do
    wall=$(cut -d, -f1 "$work/$w.$side.times" | median)
    user=$(cut -d, -f2 "$work/$w.$side.times" | median)
    peak=$(cut -d, -f3 "$work/$w.$side.times" | median)
    instr=-; cycles=-
    if [ $have_perf = yes ]; then
      run $perf_prefix perf stat -x, -e $events -o "$work/perf" -- $w $side
      instr=$(awk -F, '/instructions/ && $1 ~ /^[0-9]+$/ { s += $1 } END { printf "%.2f", s / 1e9 }' "$work/perf")
      cycles=$(awk -F, '/cycles/ && $1 ~ /^[0-9]+$/ { s += $1 } END { printf "%.2f", s / 1e9 }' "$work/perf")
    fi
    printf '%-8s %-4s %6s %6s %8.1f %8s %8s\n' $w $side "$wall" "$user" \
      "$(echo "$peak" | awk '{ print $1 / 1024 }')" "$instr" "$cycles"
  done
done
