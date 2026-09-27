#!/bin/sh
. ../../testenv.sh
# Phase 11 A16: poc -g gives gdb and lldb the procedures' names, the
# source lines, and the variables: parameters, locals and module variables,
# of the basic types, records, arrays and pointers. The program is built at
# -opt 0 (as the docs advise for debugging), then stopped at a procedure of
# an imported module (by name) and at lines of both modules; each
# backtrace is reduced to "name file:line" per Oberon frame and each value
# to "expression = value", the same for either debugger: gdb 7 or later
# where there is one (OpenBSD's base gdb is 6.3, which cannot read LLVM's
# DWARF, but its gdb package installs a newer one as egdb), lldb otherwise.
# Skips itself, still passing, on a machine with neither.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")

debugger=none
for g in egdb gdb
do
  if command -v $g >/dev/null 2>&1 &&
     [ "$($g --version 2>/dev/null | head -1 | sed 's/.* \([0-9][0-9]*\)\.[0-9].*/\1/')" -ge 7 ] 2>/dev/null
  then debugger=gdb; gdb=$g; break
  fi
done
if [ $debugger = none ] && command -v lldb >/dev/null 2>&1
then debugger=lldb
fi
if [ $debugger = none ]
then
  echo "SKIPPED: no gdb 7 or later and no lldb here"
  printf 'PASSED (skipped): %s\n\n' "$PWD"
  exit 0
fi

poc -g -opt 0 -o "$exe" -build debug.mod >result 2>&1
"./$exe" >>result

# the Oberon frames of a stop at $1: "name file:line", innermost first,
# up to main (beyond it is the C runtime, which FreeBSD's crt1 gives lines)
frames() {
  if [ $debugger = gdb ]
  then
    $gdb -batch -nx -ex "break $1" -ex run -ex bt "./$exe" 2>/dev/null |
      awk '/ in main \(/ { exit } { print }' |
      sed -n 's/^#[0-9]* *\(0x[0-9a-f]* in \)\{0,1\}\([^ ]*\) (.*) at \(.*\)$/\2 \3/p'
  else
    lldb -b -o "b $1" -o run -o bt "./$exe" 2>/dev/null |
      awk '/^\(lldb\) bt/ { f = 1; next } /`main( |$)/ { exit } f' |
      sed -n 's/^ *\* *frame/frame/; s/^ *frame #[0-9]*: 0x[0-9a-f]* [^`]*`\([^ (]*\)\((.*)\)\{0,1\} at \([^:]*:[0-9]*\).*$/\1 \3/p'
  fi | sed 's|^\([^ ]*\) .*/\([^/]*\)$|\1 \2|'
}

# the parameters and local variables at a stop at $1, "name = value",
# sorted (the debuggers list them in different orders; lldb also shows the
# type, "(INTEGER) x = 3")
variables() {
  if [ $debugger = gdb ]
  then
    $gdb -batch -nx -ex "break $1" -ex run -ex 'info args' -ex 'info locals' "./$exe" 2>/dev/null |
      grep '^[A-Za-z_$][A-Za-z0-9_$]* = '
  else
    lldb -b -o "b $1" -o run -o 'frame variable' "./$exe" 2>/dev/null |
      awk '/^\(lldb\) frame variable/ { f = 1; next } f' |
      sed -n 's/^([^)]*) \([A-Za-z_$][A-Za-z0-9_$]* = .*\)$/\1/p'
  fi | sort
}

# the values of the expressions $2... at a stop at $1, "expression = value"
# (a CHAR array's trailing 0Xs, which gdb shows and lldb does not, left out)
values() {
  stop=$1; shift
  if [ $debugger = gdb ]
  then
    set -- "$@"
    args=""
    for e in "$@"; do args="$args -ex 'print $e'"; done
    eval "\$gdb -batch -nx -ex \"break \$stop\" -ex run $args \"./\$exe\"" 2>/dev/null |
      sed -n 's/^\$[0-9]* = //p' |
      while read -r v; do printf '%s = %s\n' "$1" "$v"; shift; done
  else
    args=""
    for e in "$@"; do args="$args -o 'p $e'"; done
    eval "lldb -b -o \"b \$stop\" -o run $args \"./\$exe\"" 2>/dev/null |
      awk '/^\(lldb\) p / { e = substr($0, 10); getline; sub(/^\([^)]*\) (\$[0-9]+ = )?/, ""); print e " = " $0 }'
  fi | sed 's/\(\\000\)\{1,\}"/"/; s/", .\\000. <repeats [0-9]* times>/"/'
}

echo "stopped in DebugLib.Square:" >>result
frames DebugLib.Square >>result
echo "stopped at debug.mod:12:" >>result
frames debug.mod:12 >>result
echo "variables at DebugLib.mod:17:" >>result
variables DebugLib.mod:17 >>result
echo "values at DebugLib.mod:28:" >>result
values DebugLib.mod:28 'c->n' r.n r.name 'r.scores[1]' total >>result
echo "values at debug.mod:18:" >>result
values debug.mod:18 'c->n' kept.name 'kept.scores[1]' total >>result
. ../../testresult.sh
