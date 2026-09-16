#!/bin/sh
. ../../testenv.sh
poc -check param-mode-mismatch.mod >result
. ../../testresult.sh
