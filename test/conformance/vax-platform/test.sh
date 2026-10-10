#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
# 15, proposals 3 to 8): rtl/vax's Platform, and Directories, which both
# runtimes have (MakePath, IsDirectory, MakeDirectory, pathSeparator). poc
# -emit-macro32's output for PlatformUse.mod, rtl/vax/Platform.Mod and
# Directories.Mod against the reviewed expected-vax.mar,
# expected-vax-Platform.mar and expected-vax-Directories.mar, assembled
# and run under the debugger on the VAX where the development system can
# be used (../../vaxfixture.sh). Then, for -O2 and -OC, PlatformOut built
# by the LLVM backend and run here on Unix names, which must print
# output.expected, and built for the VAX and run there on VMS names
# (vax_do, guest-run.com), which must print guest-run.expected.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
rm -f PlatformOut.com
rm -rf made
: >result
vax_mar PlatformUse -import-path $rtl
# status N: the status VMS has where LLVM exits with N (design section 14,
# item 10)
status() {
  if [ "$1" = 0 ]; then echo "status: %X00000001"
  else printf 'status: %%X%08X\n' $((0x10000000 + 8 * $1 + 2))
  fi
}
for model in -O2 -OC; do
  rm -f *.sym
  poc $model -o vax-platform -build PlatformOut.mod >>result 2>&1
  echo "LLVM build $model exit $?" >>result
  : >doomed.tmp
  POC_PLATFORM_TEST='[A]:[B]' ./vax-platform . no-such-directory made/sub POC_PLATFORM_TEST >output 2>&1
  status $? >>output
  [ -f doomed.tmp ] && echo "left: doomed.tmp" >>output
  rm -rf made doomed.tmp
  cmp -s output output.expected || { echo "the LLVM backend's output, $model:" >>result; diff output.expected output >>result; }
  rm -f *.sym
  poc $model -target vax-dec-vms -import-path $rtl -build PlatformOut.mod >>result 2>&1
  echo "VAX build $model exit $?" >>result
  vax_do guest-run.com guest-run.expected PlatformOut.com PlatformOut.mar Platform.mar Directories.mar Modules.mar Out.mar \
    LineOutput.mar $rtl/PocRtl.mar
done
rm -f output
. ../../testresult.sh
