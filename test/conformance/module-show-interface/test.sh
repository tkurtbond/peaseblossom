#!/bin/sh
. ../../testenv.sh
# stdout of -show-interface, then the same module's .sym for contrast
: >result
poc -show-interface shapes.mod >>result 2>&1
echo "--- .sym:" >>result
poc -emit-interface shapes.mod >/dev/null
cat shapes.sym >>result
echo "--- client (imports shapes):" >>result
poc -show-interface client.mod >>result 2>&1
if [ -f client.sym ]; then echo "client.sym WRITTEN" >>result; else echo "client.sym not written" >>result; fi
. ../../testresult.sh
