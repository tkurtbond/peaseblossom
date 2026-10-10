#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 10): the real POC_TRAP and POC_HALT. poc -emit-macro32's output
# for VaxTraps.mod, under -trap-location and -range-checks, against the
# reviewed expected-vax.mar, assembled on the VAX where the development
# system can be used (../../vaxfixture.sh). Then Traps, for each case of
# TrapMode.mode, built by the LLVM backend and run here, and built for the
# VAX and run there with rtl/vax/PocRtl.mar (vax_do, guest-run.com): with
# -trap-location, for every case, and without it, for cases 4 and 6. Each
# case prints its output, its status, as VMS has it, and its message:
# output.expected and plain.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f Traps.com TrapMode*.mod TrapMode*.mar
: >result
vax_mar VaxTraps -trap-location -range-checks
rm -f *.sym Traps.mar TrapLib.mar Out.mar LineOutput.mar
# status N: the status VMS has where LLVM exits with N (section 14, item 10)
status() {
  if [ "$1" = 0 ]; then echo "status: %X00000001"
  else printf 'status: %%X%08X\n' $((0x10000000 + 8 * $1 + 2))
  fi
}
# run <expected> <option>... -- <case>...: for each case, Traps built by
# both backends with the options, the LLVM one run here, and the VAX one's
# modules, with TrapMode<case>.mar for each case, sent to the VAX
run() {
  expected=$1; shift
  options=
  while [ "$1" != -- ]; do options="$options $1"; shift; done
  shift
  : >output
  rm -f TrapMode*.mar
  for n; do
    printf 'MODULE TrapMode;\n  VAR mode*: INTEGER;\nBEGIN\n  mode := %s\nEND TrapMode.\n' "$n" >TrapMode.mod
    rm -f *.sym
    poc -O2 $options -o vax-traps -build Traps.mod >>result 2>&1 || echo "LLVM build of case $n failed" >>result
    ./vax-traps >run.out 2>run.err
    st=$?
    { echo "== case $n, build status: %X10000001"; cat run.out; status $st; cat run.err; } >>output
    rm -f *.sym
    poc -O2 $options -target vax-dec-vms -import-path $rtl -build Traps.mod >>result 2>&1 \
      || echo "VAX build of case $n failed" >>result
    mv TrapMode.mar "TrapMode$n.mar"
  done
  cmp -s output "$expected" || { echo "the LLVM backend's output, $options:" >>result; diff "$expected" output >>result; }
  vax_do guest-run.com "$expected" Traps.com Traps.mar TrapLib.mar Out.mar LineOutput.mar $rtl/PocRtl.mar TrapMode*.mar
  rm -f TrapMode*.mar TrapMode.mod Traps.com Traps.mar TrapLib.mar Out.mar LineOutput.mar *.sym run.out run.err output
}
run output.expected -trap-location -range-checks -- 1 2 3 4 5 6 7 8 9
run plain.expected -range-checks -- 4 6
. ../../testresult.sh
