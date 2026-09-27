#!/bin/sh
. ../../testenv.sh
# Phase 11 A25, reopened 2026-09-26: "_" and "$" in the names of a module,
# its constants, types, fields, procedures, parameters and variables, first
# character included, across modules (Ss$Def.sym) and named like the
# backend's own generated names.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
poc_build_run dollar.mod
cat 'Ss$Def.sym' >>result
. ../../testresult.sh
