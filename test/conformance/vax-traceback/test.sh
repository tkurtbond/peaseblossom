#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 5a: the traceback records poc writes in every
# object (doc/developer/vax-object-language.md, section 16), for
# VaxTrace, whose procedures nest and whose loops give a line two ranges
# of code: printed by vax-image -records and compared with
# expected-VaxTrace.records on every host (the creation time fixed by
# SOURCE_DATE_EPOCH, poc's version left out); and on the VAX (vax_do,
# guest-traceback.com), linked from poc's object with poc's runtime from
# MACRO, run as it is, whose divide by zero's traceback must name each
# procedure and line, then linked /DEBUG and run under the debugger with
# trace.dbg's breakpoints and steps by line and routine
# (guest-traceback.expected; its PCs, which depend on the runtime's size,
# masked).
. ../../vaxfixture.sh
vax_image=${VAX_IMAGE:-../../../build/bin/vax-image}
SOURCE_DATE_EPOCH=1792281600; export SOURCE_DATE_EPOCH
: >result
rm -f *.obj *.sym *.mar *.image VaxTrace.records
poc -emit-vax-object VaxTrace.mod >>result 2>&1
echo "exit $?" >>result
"$vax_image" -records VaxTrace.obj 2>&1 \
  | sed 's/"Peaseblossom poc [^"]*"/"Peaseblossom poc"/' >VaxTrace.records
if diff VaxTrace.records expected-VaxTrace.records >records-diff 2>&1; then
  echo "VaxTrace.records matches expected-VaxTrace.records" >>result
else
  echo "VaxTrace.records differs from expected-VaxTrace.records:" >>result
  cat records-diff >>result
fi
rm -f records-diff
vax_mask=yes
vax_do guest-traceback.com guest-traceback.expected VaxTrace.obj trace.dbg ../../../rtl/vax/PocRtl.mar
rm -f *.sym *.mar
. ../../testresult.sh
