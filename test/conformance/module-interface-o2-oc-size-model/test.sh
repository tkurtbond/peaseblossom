#!/bin/sh
. ../../testenv.sh
mkdir -p o2 oc
poc -output-dir o2 -emit-interface bounds.mod >/dev/null
poc -OC -output-dir oc -emit-interface bounds.mod >/dev/null
{ echo "-O2:"; cat o2/bounds.sym; echo "-OC:"; cat oc/bounds.sym; } >result
. ../../testresult.sh
