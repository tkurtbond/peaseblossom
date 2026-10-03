#!/bin/sh
. ../../testenv.sh
# -check searches the library path too (Phase 13 step 6): the host's triple
# and poc's own library directory masked
unset POC_LIBRARY_PATH
mask() { sed -e "s|$(clang -dumpmachine)|<triple>|g" -e 's|library path ([^)]*)|library path (<poc'"'"'s library>)|'; }
(cd lib && poc -emit-interface greeter.mod >/dev/null)
poc -check client.mod 2>&1 | mask >result
. ../../testresult.sh
