#!/bin/sh
. ../../testenv.sh
poc -check cyclic-type.mod >result
. ../../testresult.sh
