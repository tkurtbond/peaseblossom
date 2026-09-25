#!/bin/sh
. ../../testenv.sh
poc -check call-of-result.mod >result
. ../../testresult.sh
