#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 6 (doc/developer/vax-macro32-backend.md, section
# 17): an & or OR whose right side calls a procedure, assigned through a
# pointer. poc -emit-macro32's output for VaxShortCircuit.mod against the
# reviewed expected-vax.mar, assembled on the VAX where the development
# system can be used (../../vaxfixture.sh). Then ShortOut, built by the
# LLVM backend and run here, which must print output.expected; the same
# program built for the VAX and run there is in test/vax-suite.list.
. ../../vaxfixture.sh
: >result
vax_mar VaxShortCircuit
rm -f *.sym
poc -o vax-short-circuit-call -build ShortOut.mod >>result 2>&1
echo "LLVM build exit $?" >>result
./vax-short-circuit-call >output 2>&1
echo "exit $?" >>output
cmp -s output output.expected || { echo "the LLVM backend's output:" >>result; diff output.expected output >>result; }
rm -f output
. ../../testresult.sh
