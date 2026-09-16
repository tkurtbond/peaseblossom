#!/bin/sh
. ../../testenv.sh
poc -check is-operator.mod >result
. ../../testresult.sh
