#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4's end (doc/developer/vax-macro32-backend.md,
# section 15, proposal 10): poc's own source, with rtl/vax and a BuildInfo
# for a poc that runs on VAX/VMS (tools/build-info gen vax-dec-vms), built
# with -build for the VAX, under -OC as poc itself needs; then, where the
# VAX development system can be used, assembled and linked there into
# POC.EXE, which runs as a foreign command (guest-run.com). Its options
# are given unquoted, so DCL uppercases them, and poc on VMS matches them
# without regard to case (section 10; section 15, proposal 6): -HELP
# prints what this poc's -help does, -VERSION names vax-dec-vms and no
# clang, -TARGET takes vax-dec-vms only, and an unknown option is an error.
. ../../vaxfixture.sh
root=../../..
rm -rf gen obj
: >result
"$root/tools/build-info" gen vax-dec-vms >>result 2>&1
mkdir obj
(cd obj && poc -OC -target vax-dec-vms -import-path ../$root/src/front -import-path ../$root/src/back/llvm \
  -import-path ../$root/src/back/vax -import-path ../$root/rtl/vax -import-path ../$root/src/driver \
  -import-path ../gen -build ../$root/src/driver/Poc.Mod) >>result 2>&1
echo "VAX build exit $?" >>result
# what POC.EXE must print, from this poc and the BuildInfo just written
commit=$(sed -n 's/^ *commit\* *= *"\(.*\)";.*/\1/p' gen/BuildInfo.Mod)
version=$(poc -version | sed -n '1s/^poc \([^ ]*\).*/\1/p')
poc -help >help.expected 2>&1
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
  echo "== POC -NOSUCH"
  echo "run status: %X1000000A"
  echo "poc: unknown option -nosuch"
  echo "run poc -help for the commands and options"
} >guest-run.expected
vax_do guest-run.com guest-run.expected obj/Poc.com obj/*.mar $root/rtl/vax/PocRtl.mar
rm -rf gen obj help.expected guest-run.expected
. ../../testresult.sh
