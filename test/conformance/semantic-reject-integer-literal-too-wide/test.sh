#!/bin/sh
. ../../testenv.sh
poc -check integer-literal-too-wide.mod >result
. ../../testresult.sh
