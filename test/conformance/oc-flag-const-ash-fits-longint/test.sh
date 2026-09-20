#!/bin/sh
. ../../testenv.sh
{ echo "-O2:"; poc -check fits.mod; echo "-OC:"; poc -OC -check fits.mod; } >result
. ../../testresult.sh
