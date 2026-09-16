#!/bin/sh
. ../../testenv.sh
poc -check type-bound-procedures.mod >result
. ../../testresult.sh
