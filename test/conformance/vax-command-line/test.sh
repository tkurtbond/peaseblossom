#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
# 15, proposal 6): rtl/vax's Modules, the command line. poc
# -emit-macro32's output for CommandLine.mod and rtl/vax/Modules.Mod
# against the reviewed expected-vax.mar and expected-vax-Modules.mar,
# assembled and run under the debugger on the VAX where the development
# system can be used (../../vaxfixture.sh). Then, for -O2 and -OC,
# ArgsOut built by the LLVM backend and run here with the arguments the
# shell gives it, which must print output.expected, and built for the VAX
# and run there as a foreign command and by RUN (vax_do, guest-run.com),
# which must print guest-run.expected: DCL makes text outside quotes
# uppercase, and Modules splits the line as DCL's own rule has it.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f ArgsOut.com
: >result
vax_mar CommandLine -import-path $rtl
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-command-line -build ArgsOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  ./vax-command-line -o Hello mixedCase 'a"b"c' 'x"y' '' 'two  spaces' tab >output 2>&1
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build ArgsOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected ArgsOut.com ArgsOut.mar Modules.mar Out.mar LineOutput.mar $rtl/PocRtl.mar
done
rm -f output
. ../../testresult.sh
