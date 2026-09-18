#!/bin/sh
. ../../testenv.sh
poc -dump-layout mixed.mod >result
. ../../testresult.sh
