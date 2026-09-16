#!/bin/sh
. ../../testenv.sh
poc -check exit-outside-loop.mod >result
. ../../testresult.sh
