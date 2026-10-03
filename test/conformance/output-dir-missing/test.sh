#!/bin/sh
. ../../testenv.sh
# -output-dir names a directory that is not there: poc makes it (as -library
# does; Phase 13 step 6), and says so only when it cannot, here under a file.
rm -rf nosuchdir
poc -output-dir nosuchdir/sub -emit-interface lib.mod >result 2>&1
ls nosuchdir/sub >>result
poc -output-dir lib.mod/sub -emit-interface lib.mod >>result 2>&1
rm -rf nosuchdir
. ../../testresult.sh
