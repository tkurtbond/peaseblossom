#!/bin/sh
. ../../testenv.sh
poc -check procedure-typed-call.mod >result
. ../../testresult.sh
