#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md, section
# 16, proposal 7): SYSTEM.VAL into a HUGEINT. poc -emit-macro32's output for
# VaxVal.mod against the reviewed expected-vax.mar, assembled on the VAX
# where the development system can be used (../../vaxfixture.sh). Then
# ValOut, built by the LLVM backend and run here, which must print
# output.expected; the same program built for the VAX and run there is in
# test/vax-suite.list.
. ../../vaxfixture.sh
: >result
vax_mar VaxVal
rm -f *.sym
poc -o vax-val -build ValOut.mod >>result 2>&1
echo "LLVM build exit $?" >>result
./vax-val >output 2>&1
echo "exit $?" >>output
cmp -s output output.expected || { echo "the LLVM backend's output:" >>result; diff output.expected output >>result; }
rm -f output
. ../../testresult.sh
