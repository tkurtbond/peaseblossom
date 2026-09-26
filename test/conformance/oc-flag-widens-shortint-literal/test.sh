#!/bin/sh
. ../../testenv.sh
{ echo "-O2:"; poc -check widen.mod; echo "-OC:"; poc -OC -check widen.mod; } >result 2>&1
. ../../testresult.sh
