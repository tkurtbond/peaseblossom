#!/bin/sh
# How much memory poc needs to compile its own source for VAX/VMS
# (doc/developer/vms-memory.md, step 1a): the peak resident size of poc
# writing every module of poc for vax-dec-vms as one program, as
# tools/bootstrap/vax-v1 does, and then of poc compiling each module alone
# (-compile) against the others' .sym files, largest first. On a 32-bit
# host (cymoril) poc's pointers and SYSTEM.ADDRESS are the VAX's size, so
# its figures are the nearest to the guest's.
#
# Usage: tools/bench/poc-memory.sh [-poc <poc>] [-vax-macro32]
#
# <poc> is the poc measured, build/bin/poc by default; objects are written
# unless -vax-macro32 is given. With POC_MEMORY_CENSUS set in the
# environment, each run's census goes to its own log, kept in the work
# directory, which is then printed and not removed. Needs /usr/bin/time:
# GNU's -f on Linux, -l on the BSDs.
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
poc=$ROOT/build/bin/poc
way=-vax-objects
while [ $# -gt 0 ]; do
  case $1 in
    -poc) poc=$2; shift 2 ;;
    -vax-macro32) way=-vax-macro32; shift ;;
    *) echo "usage: $0 [-poc <poc>] [-vax-macro32]" >&2; exit 2 ;;
  esac
done
[ -x "$poc" ] || { echo "$0: no $poc" >&2; exit 1; }
unset POC_IMPORT_PATH

work=$(mktemp -d "${TMPDIR:-/tmp}/poc-memory.XXXXXX")
if [ -z "$POC_MEMORY_CENSUS" ]; then trap 'rm -rf "$work"' EXIT; fi
mkdir "$work/gen" "$work/out"
"$ROOT/tools/build-info" "$work/gen" vax-dec-vms >/dev/null

dirs="$ROOT/src/front $ROOT/src/back/vax $ROOT/src/back/vax/vms $ROOT/rtl/vax
  $ROOT/src/driver $ROOT/src/driver/no-llvm $work/gen"
paths=
for d in $dirs; do paths="$paths -import-path $d"; done

# measure <name> <poc arguments...>: runs poc in $work/out, its output in
# $work/<name>.log, and appends "<peak KB> <name>" to $work/peaks
measure() {
  name=$1; shift
  case $(uname -s) in
    Linux)
      (cd "$work/out" && /usr/bin/time -f '%M' -o "$work/$name.time" "$poc" "$@") \
        >"$work/$name.log" 2>&1 || { cat "$work/$name.log" >&2; exit 1; }
      kb=$(tail -1 "$work/$name.time") ;;
    *)
      (cd "$work/out" && /usr/bin/time -l "$poc" "$@") \
        >"$work/$name.log" 2>&1 || { cat "$work/$name.log" >&2; exit 1; }
      kb=$(awk '/maximum resident set size/ { print $1 }' "$work/$name.log") ;;
  esac
  echo "$kb $name" >>"$work/peaks"
}

# poc as one program, as vax-v1 writes it; this leaves every module's .sym
measure all-of-poc -OC -target vax-dec-vms $way $paths -build "$ROOT/src/driver/Poc.Mod"
whole=$(cat "$work/peaks")
: >"$work/peaks"

# each module alone, its imports from the .sym files just written
for sym in "$work"/out/*.sym; do
  module=$(basename "$sym" .sym)
  source=
  for d in $dirs; do
    if [ -f "$d/$module.Mod" ]; then source=$d/$module.Mod; break; fi
  done
  [ -n "$source" ] || { echo "$0: no source for $module" >&2; exit 1; }
  measure "$module" -OC -target vax-dec-vms $way -import-path "$work/out" $paths -compile "$source"
done

echo "poc: $poc ($way, $(uname -sm))"
echo "$whole" | awk '{ printf "%8.1f MB  %s\n", $1 / 1024, $2 }'
sort -rn "$work/peaks" | awk '{ printf "%8.1f MB  %s\n", $1 / 1024, $2 }'
if [ -n "$POC_MEMORY_CENSUS" ]; then echo "logs, with each run's census: $work"; fi
