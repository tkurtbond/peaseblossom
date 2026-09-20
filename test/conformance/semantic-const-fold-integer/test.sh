#!/bin/sh
. ../../testenv.sh
{ echo "-O2:"; poc -check const-fold-integer.mod; } >result
. ../../testresult.sh
