#!/bin/sh
. ../../testenv.sh
poc -check bad-pointer-base.mod >result
. ../../testresult.sh
