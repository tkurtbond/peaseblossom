#!/bin/sh
. ../../testenv.sh
poc -check wide.mod >result 2>&1
. ../../testresult.sh
