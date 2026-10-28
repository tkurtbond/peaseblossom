#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4's end (doc/developer/vax-macro32-backend.md,
# section 15, proposal 10): poc's own source, with rtl/vax and a BuildInfo
# for a poc that runs on VAX/VMS (tools/build-info gen vax-dec-vms), built
# with -build for the VAX, under -OC as poc itself needs, writing poc's
# own objects (PLAN.md Phase 18 step 7c; doc/developer/
# vax-object-language.md, section 18.2, proposal 6); then, where the VAX
# development system can be used, sent there in binary, converted by
# tools/vax-do and linked into POC.EXE with no MACRO but PocRtl.mar's,
# which runs as a foreign command (guest-run.com). Its options
# are given unquoted, so DCL uppercases them, and poc on VMS matches them
# without regard to case (section 10; section 15, proposal 6): -HELP
# prints what this poc's -help does, -VERSION names vax-dec-vms and no
# clang, -TARGET takes vax-dec-vms only, and an unknown option is an error.
# It is built without the LLVM back end (Phase 17 step 7;
# doc/developer/vax-macro32-backend.md, section 21, proposal 8): its -HELP
# leaves out the LLVM options and commands, and -LTO is refused. Then
# POC.EXE builds Sums.mod with its default on VMS, poc's own objects
# written through RecordFiles (PLAN.md Phase 18 step 6e; doc/developer/
# vax-object-language.md, section 17.7): its procedure must be the one
# this poc writes with -vax-objects, less the lines that convert objects
# sent from here and with the source named as DCL passes it, in capitals,
# so that it links SUMS.OBJ as poc wrote it, and SUMS.EXE
# must print its three sums.
. ../../vaxfixture.sh
root=../../..
rm -rf gen obj sums
: >result
"$root/tools/build-info" gen vax-dec-vms >>result 2>&1
mkdir obj
(cd obj && poc -OC -target vax-dec-vms -vax-objects -import-path ../$root/src/front \
  -import-path ../$root/src/back/vax -import-path ../$root/src/back/vax/vms -import-path ../$root/rtl/vax -import-path ../$root/src/driver \
  -import-path ../$root/src/driver/no-llvm -import-path ../gen -build ../$root/src/driver/Poc.Mod) >>result 2>&1
echo "VAX build exit $?" >>result
mkdir sums
cp Sums.mod sums/
(cd sums && poc -target vax-dec-vms -vax-objects -build Sums.mod) >>result 2>&1
echo "VAX build Sums exit $?" >>result
# what POC.EXE must print, from this poc and the BuildInfo just written
commit=$(sed -n 's/^ *commit\* *= *"\(.*\)";.*/\1/p' gen/BuildInfo.Mod)
version=$(poc -version | sed -n '1s/^poc \([^ ]*\).*/\1/p')
poc -help 2>&1 | grep -Ev '^  -(emit-llvm-ir|dump-llvm-types|opt|lto|rebuild|static|c-flag|verbose) |^  -link <arg> |^  -build <file> <o>\.o|^ +\(and object files' \
  >help.expected
{
  echo "build status: %X10000001"
  for option in -HELP -H; do
    echo "== POC $option"; cat help.expected; echo "run status: %X00000001"
  done
  for option in -VERSION "-TARGET VAX-DEC-VMS -VERSION"; do
    echo "== POC $option"
    if [ -n "$commit" ]; then echo "poc $version ($commit)"; else echo "poc $version"; fi
    echo "target vax-dec-vms, size model -O2"
    echo "run status: %X00000001"
  done
  echo "== POC -TARGET X86_64-LINUX-GNU -VERSION"
  echo "run status: %X1000000A"
  echo "poc: -target x86_64-linux-gnu is not available on VAX/VMS"
  echo "== POC -LTO -VERSION"
  echo "run status: %X1000000A"
  echo "poc: -lto is not available on VAX/VMS, where poc has no LLVM back end"
  echo "== POC -NOSUCH"
  echo "run status: %X1000000A"
  echo "poc: unknown option -nosuch"
  echo "run poc -help for the commands and options"
  echo "== POC -BUILD SUMS.MOD"
  echo "run status: %X00000001"
  sed '/^\$ ! An object sent in binary from Linux or a BSD/d; /^\$ ! is converted first, by OBJCONVERT/d
    /^\$ IF F\$FILE_ATTRIBUTES(".*\.OBJ", "RFM")/,/^\$CONVERTED_[0-9]*:$/d
    s/for Sums\.mod:/for SUMS.MOD:/' sums/Sums.com
  echo "link status: %X10000001"
  echo "sum of 1 to 10 is 55"
  echo "sum of 1 to 100 is 5050"
  echo "sum of 50 to 60 is 605"
} >guest-run.expected
vax_do guest-run.com guest-run.expected obj/Poc.com obj/*.obj $root/rtl/vax/PocRtl.mar Sums.mod
rm -rf gen obj sums help.expected guest-run.expected
. ../../testresult.sh
