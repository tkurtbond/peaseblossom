#!/bin/sh
. ../../testenv.sh
poc -check self-import.mod >result
. ../../testresult.sh
