#!/bin/sh
. ../../testenv.sh
poc -check names.mod >result 2>&1
echo "exit=$?" >>result
. ../../testresult.sh
