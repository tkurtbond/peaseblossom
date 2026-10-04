#!/bin/sh
. ../../testenv.sh
# Phase 14: indexed array elements the checker rejects - an index given twice
# (by two labels, or by a positional element and a label), outside the bounds,
# not a constant integer, an empty range, a positional element past the end
# after one, an index in a record literal, and one in a set
poc -check indexes.mod >result 2>&1
. ../../testresult.sh
