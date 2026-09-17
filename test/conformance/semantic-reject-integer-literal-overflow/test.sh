#!/bin/sh
. ../../testenv.sh
poc -check integer-literal-overflow.mod >result
. ../../testresult.sh
