#!/bin/sh
. ../../testenv.sh
# Builds every runtime fixture that has a program to run as a real 32-bit
# executable (-target i686-unknown-linux-gnu, which also proves -build now
# links for the target rather than the host) and checks that its output is
# exactly what its 64-bit sibling fixture expects: the word size must not
# change what a program prints. Skips itself, still passing, on a machine
# that cannot run 32-bit x86 executables (see i686_can_run).
if ! i686_can_run
then
  echo "SKIPPED: no 32-bit x86 C runtime here (Fedora: dnf install glibc-devel.i686)"
  printf 'PASSED (skipped): %s\n\n' "$PWD"
  exit 0
fi

here=$PWD
triple=i686-unknown-linux-gnu
: >result

# name of a sibling fixture, its main source file
check() {
  dir=$1; src=$2
  # the sibling's own directory, so its library modules are found; every
  # generated file goes to this fixture's directory instead
  ( cd "../$dir" &&
    POC_IMPORT_PATH=../../../rtl/llvm \
      poc -target $triple -output-dir "$here" -o "$here/program.i686" -build "$src" >/dev/null 2>&1 )
  if [ -x program.i686 ]
  then
    file program.i686 | grep -q 'ELF 32-bit' || echo "$dir: NOT A 32-BIT EXECUTABLE" >>result
    ./program.i686 >program.out 2>&1
    tail -n +2 "../$dir/expected" >want.out
    if diff -b want.out program.out >/dev/null
    then echo "$dir: same" >>result
    else echo "$dir: DIFFERENT" >>result; diff -b want.out program.out >>result
    fi
  else
    echo "$dir: BUILD FAILED" >>result
  fi
  rm -f program.i686 program.out want.out *.ll *.sym
}

check llvm-hello-world hello.mod
check llvm-const-decls const-decls.mod
check llvm-arrays-records arrrecflow.mod
check llvm-control-flow ctrlflow.mod
check llvm-procedures procs.mod
check llvm-predeclared predeclared.mod
check llvm-multi-module client.mod
check llvm-reals reals.mod
check llvm-sets sets.mod
check llvm-char-arrays chararrays.mod
check llvm-string-consts client.mod
check llvm-system system.mod
check llvm-gc-collect gc.mod
check llvm-gc-tracing gctracing.mod
. ../../testresult.sh
