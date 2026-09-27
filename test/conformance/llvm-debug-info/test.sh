#!/bin/sh
. ../../testenv.sh
# Phase 11 A16: poc -g gives gdb and lldb the procedures' names and the
# source lines. The program is built at -opt 0 (as the docs advise for
# debugging), then stopped at a procedure of an imported module (by name)
# and at a line of the main one, and each backtrace is reduced to "name
# file:line" per Oberon frame, the same for either debugger: gdb 7 or later
# where there is one, lldb otherwise. Skips itself, still passing, on a
# machine with neither (OpenBSD's base gdb 6.3 cannot read LLVM's DWARF).
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")

debugger=none
if command -v gdb >/dev/null 2>&1 &&
   [ "$(gdb --version 2>/dev/null | head -1 | sed 's/.* \([0-9][0-9]*\)\.[0-9].*/\1/')" -ge 7 ] 2>/dev/null
then debugger=gdb
elif command -v lldb >/dev/null 2>&1
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
    gdb -batch -nx -ex "break $1" -ex run -ex bt "./$exe" 2>/dev/null |
      awk '/ in main \(/ { exit } { print }' |
      sed -n 's/^#[0-9]* *\(0x[0-9a-f]* in \)\{0,1\}\([^ ]*\) (.*) at \(.*\)$/\2 \3/p'
  else
    lldb -b -o "b $1" -o run -o bt "./$exe" 2>/dev/null |
      awk '/^\(lldb\) bt/ { f = 1; next } /`main( |$)/ { exit } f' |
      sed -n 's/^ *\* *frame/frame/; s/^ *frame #[0-9]*: 0x[0-9a-f]* [^`]*`\([^ ]*\) at \([^:]*:[0-9]*\).*$/\1 \2/p'
  fi | sed 's|^\([^ ]*\) .*/\([^/]*\)$|\1 \2|'
}

echo "stopped in DebugLib.Square:" >>result
frames DebugLib.Square >>result
echo "stopped at debug.mod:12:" >>result
frames debug.mod:12 >>result
. ../../testresult.sh
