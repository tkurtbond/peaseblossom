#!/bin/sh
. ../../testenv.sh
# -strict is for the command line's module only, also when an import comes
# as a .sym: from a library (Out, poc-rtl's) or as a compiled module's .sym
# and .o (Phase 14's "Ongoing bug fixing" 4: both were held to -strict), or
# from source with an extension among a procedure's locals (until 2026-10-11
# reported, under the importer's file name, when the backend reopened the
# procedure's body to generate it); the module's own extensions are still
# reported.
exe=$(basename "$PWD")
rm -rf built
: >result
mkdir built
poc -output-dir built -compile lib/Wide.mod >/dev/null 2>&1
poc -strict -import-path built -o "$exe" -build client.mod >>result 2>&1
"./$exe" >>result 2>&1
poc -strict -import-path built -check client.mod >>result 2>&1
poc -strict -check own.mod >>result 2>&1
poc -strict -import-path lib -o "$exe" -build uselocals.mod >>result 2>&1
"./$exe" >>result 2>&1
rm -rf built
. ../../testresult.sh
