#!/bin/sh
. ../../testenv.sh
# Under -O2 (the default), so that 10000000000 needs HUGEINT. For a 32-bit
# target: Plain's "a := SYSTEM.ADR(buf)" (the report's ADR gives a LONGINT)
# fits only where an address is as narrow as -O2's LONGINT; -check judged
# every module at 32 bits until Phase 14's "Ongoing bug fixing" 2, which
# this fixture relied on unknowingly.
: >result
poc -target i686-unknown-linux-gnu -strict -check strict.mod >>result 2>&1
poc -target i686-unknown-linux-gnu -check strict.mod >>result 2>&1
. ../../testresult.sh
