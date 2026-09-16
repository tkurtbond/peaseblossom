#!/bin/sh
. ../../testenv.sh
poc -check self-referential.mod >result
. ../../testresult.sh
