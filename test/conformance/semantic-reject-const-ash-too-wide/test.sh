#!/bin/sh
. ../../testenv.sh
poc -check const-ash-too-wide.mod >result
. ../../testresult.sh
