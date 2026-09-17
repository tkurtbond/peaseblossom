#!/bin/sh
. ../../testenv.sh
poc -check integer-literal-minimal-type.mod >result
. ../../testresult.sh
