#!/bin/sh
. ../../testenv.sh
poc -check statements.mod >result
. ../../testresult.sh
