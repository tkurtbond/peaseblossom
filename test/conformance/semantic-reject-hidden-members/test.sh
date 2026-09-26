#!/bin/sh
. ../../testenv.sh
poc -emit-interface lib.mod >/dev/null
: >result
for client in field method type extfield exttype; do
  echo "== $client" >>result
  poc -check $client.mod >>result 2>&1
done
. ../../testresult.sh
