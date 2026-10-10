#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md, section
# 16, proposal 7): what tools/vax-suite's first runs found. poc -OC
# -emit-macro32's output for VaxWidenNew.mod against the reviewed
# expected-vax.mar, assembled on the VAX where the development system can
# be used (../../vaxfixture.sh). Then WidenNewOut, built by the LLVM
# backend and run here, which must print output.expected and trap (7); the
# same program built for the VAX and run there is in test/vax-suite.list.
# -OC only: under -O2 an ADDRESS is no LONGINT on a 64-bit host.
. ../../vaxfixture.sh
: >result
vax_mar VaxWidenNew -OC
rm -f *.sym
poc -OC -o vax-widen-and-new -build WidenNewOut.mod >>result 2>&1
echo "LLVM build exit $?" >>result
./vax-widen-and-new >output 2>&1
echo "exit $?" >>output
cmp -s output output.expected || { echo "the LLVM backend's output:" >>result; diff output.expected output >>result; }
rm -f output
. ../../testresult.sh
