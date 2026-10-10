#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
# 14, item 11): ASSERT. poc -emit-macro32's output for VaxAssert.mod
# against the reviewed expected-vax.mar, assembled on the VAX where the
# development system can be used (../../vaxfixture.sh). Then Asserts, for
# each case of AssertMode.mode, built by the LLVM backend and run here, and
# built for the VAX and run there with rtl/vax/PocRtl.mar (vax_do,
# guest-run.com): with -trap-location, for every case, and without it,
# for case 3. Each case prints its output, its status, as VMS has it, and
# its message: output.expected and plain.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f Asserts.com AssertMode*.mod AssertMode*.mar
: >result
vax_mar VaxAssert
rm -f *.sym Asserts.mar Out.mar LineOutput.mar
# status N: the status VMS has where LLVM exits with N (section 14, item 10)
status() {
  if [ "$1" = 0 ]; then echo "status: %X00000001"
  else printf 'status: %%X%08X\n' $((0x10000000 + 8 * $1 + 2))
  fi
}
# run <expected> <option>... -- <case>...: for each case, Asserts built by
# both backends with the options, the LLVM one run here, and the VAX one's
# modules, with AssertMode<case>.mar for each case, sent to the VAX
run() {
  expected=$1; shift
  options=
  while [ "$1" != -- ]; do options="$options $1"; shift; done
  shift
  : >output
  rm -f AssertMode*.mar
  for n; do
    printf 'MODULE AssertMode;\n  VAR mode*: INTEGER;\nBEGIN\n  mode := %s\nEND AssertMode.\n' "$n" >AssertMode.mod
    rm -f *.sym
    poc -O2 $options -o vax-assert -build Asserts.mod >>result 2>&1 || echo "LLVM build of case $n failed" >>result
    ./vax-assert >run.out 2>run.err
    st=$?
    { echo "== case $n, build status: %X10000001"; cat run.out; status $st; cat run.err; } >>output
    rm -f *.sym
    poc -O2 $options -target vax-dec-vms -import-path $rtl -build Asserts.mod >>result 2>&1 \
      || echo "VAX build of case $n failed" >>result
    mv AssertMode.mar "AssertMode$n.mar"
  done
  cmp -s output "$expected" || { echo "the LLVM backend's output,$options:" >>result; diff "$expected" output >>result; }
  vax_do guest-run.com "$expected" Asserts.com Asserts.mar Out.mar LineOutput.mar $rtl/PocRtl.mar AssertMode*.mar
  rm -f AssertMode*.mar AssertMode.mod Asserts.com Asserts.mar Out.mar LineOutput.mar *.sym run.out run.err output
}
run output.expected -trap-location -- 1 2 3 4
run plain.expected -- 3
. ../../testresult.sh
