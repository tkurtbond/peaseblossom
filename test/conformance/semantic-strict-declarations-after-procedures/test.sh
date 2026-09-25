#!/bin/sh
. ../../testenv.sh
poc -strict -check strict.mod >result
. ../../testresult.sh
