#!/bin/sh
. ../../testenv.sh
voc crosscheck.mod -m
./crosscheck >result
. ../../testresult.sh
