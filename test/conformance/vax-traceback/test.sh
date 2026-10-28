#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 5a: the traceback records poc writes in every
# object (doc/developer/vax-object-language.md, section 16), for
# VaxTrace, whose procedures nest and whose loops give a line two ranges
# of code: printed by vax-image -records and compared with
# expected-VaxTrace.records on every host (the creation time fixed by
# SOURCE_DATE_EPOCH, poc's version and its LNM record's length left
# out); and on the VAX (vax_do, guest-traceback.com), linked from poc's
# object with poc's runtime from MACRO, run as it is, whose divide by
# zero's traceback must name each procedure and line, then linked /DEBUG and run under the debugger with
# trace.dbg's breakpoints and steps by line and routine
# (guest-traceback.expected; its PCs, which depend on the runtime's size,
# masked). Step 5b: the object poc -g writes, with the debugger records,
# printed and compared with expected-VaxTrace-g.records, and on the VAX,
# as VaxTraceG.obj, linked /DEBUG and run with source.dbg's commands,
# which show the source, VaxTrace.mod, sent with it; and VaxDescribe,
# built for the VAX by poc -build and run there, prints what
# RecordFiles.Describe gives poc -g on VMS.
. ../../vaxfixture.sh
vax_image=${VAX_IMAGE:-../../../build/bin/vax-image}
SOURCE_DATE_EPOCH=1792281600; export SOURCE_DATE_EPOCH
: >result
rtl=../../../rtl/vax
rm -rf *.obj *.sym *.mar *.image VaxTrace*.records VaxDescribe.com debug
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
poc -emit-vax-object VaxTrace.mod >>result 2>&1
echo "exit $?" >>result
"$vax_image" -records VaxTrace.obj 2>&1 \
  | sed '/ HDR, [0-9]* bytes$/{N;s/ HDR, [0-9]* bytes\(\n  LNM "Peaseblossom poc\) [^"]*"/ HDR\1"/;}' >VaxTrace.records
records_compare VaxTrace.records expected-VaxTrace.records
mkdir debug
poc -g -output-dir debug -emit-vax-object VaxTrace.mod >>result 2>&1
echo "-g exit $?" >>result
mv debug/VaxTrace.obj VaxTraceG.obj
rm -rf debug
"$vax_image" -records VaxTraceG.obj 2>&1 \
  | sed '/ HDR, [0-9]* bytes$/{N;s/ HDR, [0-9]* bytes\(\n  LNM "Peaseblossom poc\) [^"]*"/ HDR\1"/;}' >VaxTrace-g.records
records_compare VaxTrace-g.records expected-VaxTrace-g.records
written="VaxDescribe.mar RecordFiles.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar GarbageCollectedHeap.mar"
poc -target vax-dec-vms -import-path $rtl -build VaxDescribe.mod >>result 2>&1
echo "VAX build VaxDescribe exit $?" >>result
vax_mask=yes
vax_do guest-traceback.com guest-traceback.expected VaxTrace.obj VaxTraceG.obj VaxTrace.mod trace.dbg source.dbg \
  VaxDescribe.com $written $rtl/PocRtl.mar
rm -f *.sym *.mar VaxDescribe.com
. ../../testresult.sh
