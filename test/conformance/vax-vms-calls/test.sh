#!/bin/sh
. ../../testenv.sh
# Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1, proposal
# 8): VmsCalls.mod calls real VMS routines through ["VMS"] declarations,
# one for each way an argument is passed - LIB$SET_SYMBOL and
# LIB$GET_SYMBOL, strings in and out by descriptor; $TRNLNM and $GETJPIW,
# item lists and an I/O status block from VmsArguments, arguments omitted
# by NIL; $BINTIM and $ASCTIM, a quadword read-only parameter from a
# variable and from a constant; LIB$INSERT_TREE and LIB$TRAVERSE_TREE,
# Oberon procedures VMS calls back; $FAOL, an array of longwords as an
# ARRAY OF SYSTEM.BYTE; LIB$CALLG given LIB$PUT_OUTPUT's address and an Oberon
# procedure's, by SYSTEM.VAL(SYSTEM.ADDRESS, P). Built for the VAX under -O2
# and run there (vax_do, guest-run.com), with POC_VMSCALLS_LNM defined.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="VmsCalls.mar VmsArguments.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
rm -f VmsCalls.com
: >result
rm -f *.sym $written
poc -target vax-dec-vms -import-path $rtl -build VmsCalls.mod >>result 2>&1
echo "VAX build VmsCalls exit $?" >>result
vax_do guest-run.com guest-run.expected VmsCalls.com $written $rtl/PocRtl.mar
rm -f *.sym $written VmsCalls.com
. ../../testresult.sh
