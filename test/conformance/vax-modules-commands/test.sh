#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.5): rtl/vax's Modules, its list of modules and commands and voc's
# run-time error stops, with llvm-modules-commands' programs. poc
# -emit-macro32's output for commands.mod and the modules it imports,
# each with its descriptor, against the reviewed expected-vax.mar and
# expected-vax-<Module>.mar, assembled on the VAX where the development
# system can be used (../../vaxfixture.sh). Then, for -O2 and -OC, the
# five programs built for the VAX and run there (vax_do, guest-run.com),
# which must print guest-run.expected: llvm-modules-commands' expected,
# but for ModuleTable, which VMS does not have (proposal 5), the exit
# statuses, section 14, item 10's (proposal 7), and BinaryDir, the
# image's device and directory (proposal 8).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
# what poc writes here, not the expected .mar files
written="commands.mar haltcode.mar halt.mar assertcode.mar assertzero.mar Greeter.mar Modules.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar Platform.mar GarbageCollectedHeap.mar"
src=../llvm-modules-commands
programs="commands haltcode halt assertcode assertzero"
for p in $programs; do cp $src/$p.mod $p.mod; done
cp $src/Greeter.Mod Greeter.Mod
rm -f commands.com haltcode.com halt.com assertcode.com assertzero.com
: >result
vax_mar commands -import-path $rtl
for model in -O2 -OC; do
  rm -f *.sym $written
  for p in $programs; do
    poc $model -target vax-dec-vms -import-path $rtl -build $p.mod >>result 2>&1
    echo "VAX build $p $model exit $?" >>result
  done
  vax_do guest-run.com guest-run.expected commands.com haltcode.com halt.com assertcode.com assertzero.com \
    commands.mar haltcode.mar halt.mar assertcode.mar assertzero.mar Greeter.mar Modules.mar Out.mar \
    LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar Platform.mar GarbageCollectedHeap.mar $rtl/PocRtl.mar
done
rm -f *.sym $written commands.com haltcode.com halt.com assertcode.com assertzero.com
rm -f commands.mod haltcode.mod halt.mod assertcode.mod assertzero.mod Greeter.Mod
. ../../testresult.sh
