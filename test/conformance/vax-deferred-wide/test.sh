#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 6 (doc/developer/vax-macro32-backend.md, section
# 17): a wide element or field at offset 0 of a VAR parameter. poc
# -emit-macro32's output for VaxDeferredWide.mod against the reviewed
# expected-vax.mar, assembled on the VAX where the development system can
# be used (../../vaxfixture.sh). Then
# WideOut, built by the LLVM backend and run here, which must print
# output.expected; the same program built for the VAX and run there is in
# test/vax-suite.list.
. ../../vaxfixture.sh
: >result
vax_mar VaxDeferredWide
rm -f *.sym
poc -o vax-deferred-wide -build WideOut.mod >>result 2>&1
echo "LLVM build exit $?" >>result
./vax-deferred-wide >output 2>&1
echo "exit $?" >>output
cmp -s output output.expected || { echo "the LLVM backend's output:" >>result; diff output.expected output >>result; }
rm -f output
. ../../testresult.sh
