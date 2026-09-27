#!/bin/sh
. ../../testenv.sh
# chars.sym is only needed so client.mod's own check can resolve its import;
# the executable is built from chars.mod's source, which -build finds.
poc -emit-interface chars.mod >/dev/null
poc_build_run client.mod
. ../../testresult.sh
