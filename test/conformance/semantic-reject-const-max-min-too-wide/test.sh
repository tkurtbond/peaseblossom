#!/bin/sh
. ../../testenv.sh
poc -check reject-const-max-min-too-wide.mod >result
. ../../testresult.sh
