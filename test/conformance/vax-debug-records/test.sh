#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 5c: the debugger's records of variables and
# constants of the basic types (doc/developer/vax-object-language.md,
# section 16.7), for VaxDebug, which has module variables, value and VAR
# parameters, a parameter changed and so copied to the frame, locals and
# constants of each: the object poc writes without -g, which has none,
# and with -g, printed by vax-image -records and compared with
# expected-VaxDebug.records and expected-VaxDebug-g.records on every host
# (the creation time fixed by SOURCE_DATE_EPOCH, poc's version and its
# LNM record's length left out); and on the VAX (vax_do,
# guest-debug.com), the -g object linked /DEBUG and run under the
# debugger with debug.dbg's commands, which examine and deposit each
# variable and evaluate each constant
# (guest-debug.expected). Step 5d: VaxDebugTypes, whose variables and
# parameters are records, arrays, pointers, sets and open arrays, its
# -g object's records compared with expected-VaxDebugTypes-g.records, and
# on the VAX run likewise with types.dbg's commands.
. ../../vaxfixture.sh
vax_image=${VAX_IMAGE:-../../../build/bin/vax-image}
SOURCE_DATE_EPOCH=1792281600; export SOURCE_DATE_EPOCH
: >result
rtl=../../../rtl/vax
rm -rf *.obj *.sym *.mar VaxDebug*.records VaxDebugTypes*.records debug
# "<printed> matches <expected>", or the differences, to result
records_compare() {
  if diff "$1" "$2" >records-diff 2>&1; then
    echo "$1 matches $2" >>result
  else
    echo "$1 differs from $2:" >>result
    cat records-diff >>result
  fi
  rm -f records-diff
}
poc -emit-vax-object VaxDebug.mod >>result 2>&1
echo "exit $?" >>result
"$vax_image" -records VaxDebug.obj 2>&1 \
  | sed '/ HDR, [0-9]* bytes$/{N;s/ HDR, [0-9]* bytes\(\n  LNM "Peaseblossom poc\) [^"]*"/ HDR\1"/;}' >VaxDebug.records
records_compare VaxDebug.records expected-VaxDebug.records
mkdir debug
poc -g -output-dir debug -emit-vax-object VaxDebug.mod >>result 2>&1
echo "-g exit $?" >>result
mv debug/VaxDebug.obj VaxDebug.obj
rm -rf debug
"$vax_image" -records VaxDebug.obj 2>&1 \
  | sed '/ HDR, [0-9]* bytes$/{N;s/ HDR, [0-9]* bytes\(\n  LNM "Peaseblossom poc\) [^"]*"/ HDR\1"/;}' >VaxDebug-g.records
records_compare VaxDebug-g.records expected-VaxDebug-g.records
mkdir debug
poc -g -output-dir debug -emit-vax-object VaxDebugTypes.mod >>result 2>&1
echo "types -g exit $?" >>result
mv debug/VaxDebugTypes.obj VaxDebugTypes.obj
rm -rf debug
"$vax_image" -records VaxDebugTypes.obj 2>&1 \
  | sed '/ HDR, [0-9]* bytes$/{N;s/ HDR, [0-9]* bytes\(\n  LNM "Peaseblossom poc\) [^"]*"/ HDR\1"/;}' >VaxDebugTypes-g.records
records_compare VaxDebugTypes-g.records expected-VaxDebugTypes-g.records
vax_mask=yes
vax_do guest-debug.com guest-debug.expected VaxDebug.obj VaxDebug.mod debug.dbg \
  VaxDebugTypes.obj VaxDebugTypes.mod types.dbg $rtl/PocRtl.mar
rm -f *.obj *.sym *.mar
. ../../testresult.sh
