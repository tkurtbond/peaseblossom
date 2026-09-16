#!/bin/sh
. ../../testenv.sh
poc -check override-mismatch.mod >result
. ../../testresult.sh
