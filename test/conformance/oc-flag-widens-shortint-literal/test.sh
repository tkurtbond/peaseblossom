#!/bin/sh
. ../../testenv.sh
{ echo "-O2:"; poc -check widen.mod; echo "-OC:"; poc -OC -check widen.mod; } >result
. ../../testresult.sh
