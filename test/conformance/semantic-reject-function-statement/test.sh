#!/bin/sh
. ../../testenv.sh
# A function procedure cannot be called as a statement (Oberon2.pdf 10; voc's
# err 55): every way of calling one, each named, while the proper procedures
# beside them and a function in an expression are accepted. An argument
# already in error says only that.
poc -check functionstatement.mod >result 2>&1
. ../../testresult.sh
