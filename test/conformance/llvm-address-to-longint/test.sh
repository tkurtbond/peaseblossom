#!/bin/sh
. ../../testenv.sh
# An ADDRESS assigned to a LONGINT, passed as a LONGINT and returned as
# one, under -OC: the same output on 32- and 64-bit hosts.
exe=$(basename "$PWD")
: >result
poc -OC -o "$exe" -build addresstolongint.mod >build.out 2>&1
grep -v '^semantic OK' build.out >>result
"./$exe" >>result
rm -f build.out
. ../../testresult.sh
