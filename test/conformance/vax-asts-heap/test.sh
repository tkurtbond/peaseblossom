#!/bin/sh
. ../../testenv.sh
# Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
# proposals 2 and 8): AstHeap.mod's timer AST allocates batches of nodes
# while the main line allocates and collects, and every node is checked;
# run three times on the guest (guest-run.com), as an interruption at the
# wrong instruction is a matter of chance. It fails without the heap's
# protection (section 22.5 records the trial). AstNoImport.mod, the same
# program without AsynchronousTraps, must end by trap 15 each time, the
# heap re-entered by an AST (section 22.7).
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="AstHeap.mar AstNoImport.mar AsynchronousTraps.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
rm -f AstHeap.com AstNoImport.com
: >result
rm -f *.sym $written
poc -target vax-dec-vms -import-path $rtl -build AstHeap.mod >>result 2>&1
echo "VAX build AstHeap exit $?" >>result
poc -target vax-dec-vms -import-path $rtl -build AstNoImport.mod >>result 2>&1
echo "VAX build AstNoImport exit $?" >>result
vax_do guest-run.com guest-run.expected AstHeap.com AstNoImport.com $written $rtl/PocRtl.mar
rm -f *.sym $written AstHeap.com AstNoImport.com
. ../../testresult.sh
