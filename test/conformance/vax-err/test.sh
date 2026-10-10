#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
# 15, proposal 8): rtl/vax's Err. poc -emit-macro32's output for
# ErrBasics.mod, rtl/vax/Err.Mod and LineOutput.Mod against the reviewed
# expected-vax.mar, expected-vax-Err.mar and expected-vax-LineOutput.mar,
# assembled and run under the debugger on the VAX where the development
# system can be used (../../vaxfixture.sh). Then, for -O2 and -OC,
# ErrBasics and ErrTrap built by the LLVM backend and run here, and built
# for the VAX and run there with SYS$ERROR a file (vax_do,
# guest-run.com): each prints its status, as VMS has it, then what it
# wrote to the error stream, errors.expected. A last line without Ln
# ends with a record on VMS, so an LF is added to the LLVM backend's.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f ErrBasics.com ErrTrap.com
: >result
vax_mar ErrBasics -import-path $rtl
# status N: the status VMS has where LLVM exits with N (design section 14,
# item 10)
status() {
  if [ "$1" = 0 ]; then echo "status: %X00000001"
  else printf 'status: %%X%08X\n' $((0x10000000 + 8 * $1 + 2))
  fi
}
for model in -O2 -OC; do
  : >output
  for program in ErrBasics ErrTrap; do
    rm -f *.sym
    poc $model -o vax-err -build $program.mod >>result 2>&1 || echo "LLVM build of $program $model failed" >>result
    ./vax-err >run.out 2>run.err
    st=$?
    { echo "== $program, build status: %X10000001"; cat run.out; status $st; cat run.err
      [ -z "$(tail -c 1 run.err)" ] || echo; } >>output
    rm -f *.sym
    poc $model -target vax-dec-vms -import-path $rtl -build $program.mod >>result 2>&1 \
      || echo "VAX build of $program $model failed" >>result
  done
  cmp -s output errors.expected || { echo "the LLVM backend's output, $model:" >>result; diff errors.expected output >>result; }
  vax_do guest-run.com errors.expected ErrBasics.com ErrBasics.mar ErrTrap.com ErrTrap.mar Err.mar LineOutput.mar \
    $rtl/PocRtl.mar
done
rm -f output run.out run.err
. ../../testresult.sh
