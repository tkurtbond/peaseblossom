#!/bin/sh
. ../../testenv.sh
poc -check assign-readonly-field.mod >result
. ../../testresult.sh
