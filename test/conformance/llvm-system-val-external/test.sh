#!/bin/sh
. ../../testenv.sh
# PLAN.md, "Ongoing language enhancements", item 3: SYSTEM.VAL(
# SYSTEM.ADDRESS, E) of an external procedure E is the address of E's
# linkage name. Compare.Mod declares a C comparison from its part in C,
# part/Compare.c, and C's qsort; sortints passes the comparison's address
# to qsort, compares it with the address Compare itself takes, and takes
# the address of a ["C"] procedure it declares itself and of an Oberon one.
unset POC_IMPORT_PATH
rm -rf work && mkdir work && cd work || exit 1
poc -import-path ../part -o sortints -build ../sortints.mod >../result 2>&1
./sortints >>../result 2>&1
cd ..
rm -rf work
. ../../testresult.sh
