#!/bin/sh
. ../../testenv.sh
poc -check withglobalreassigned.mod >result
. ../../testresult.sh
