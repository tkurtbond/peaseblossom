#!/bin/sh
. ../../testenv.sh
poc -check dup-field.mod >result
. ../../testresult.sh
