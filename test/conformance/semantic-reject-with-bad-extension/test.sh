#!/bin/sh
. ../../testenv.sh
poc -check with-bad-extension.mod >result
. ../../testresult.sh
