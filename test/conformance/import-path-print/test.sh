#!/bin/sh
. ../../testenv.sh
poc -print-import-path >result 2>&1
echo --- >>result
POC_IMPORT_PATH=envdir1:envdir2 poc -print-import-path >>result 2>&1
echo --- >>result
poc -import-path foo -import-path bar -print-import-path >>result 2>&1
echo --- >>result
POC_IMPORT_PATH=envdir poc -import-path cliDir -print-import-path >>result 2>&1
echo --- >>result
poc -import-path a -clear-import-path -import-path b -print-import-path >>result 2>&1
echo --- >>result
POC_IMPORT_PATH=envdir poc -clear-import-path -print-import-path >>result 2>&1
. ../../testresult.sh
