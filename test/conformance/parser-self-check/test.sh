#!/bin/sh
# Robustness smoke test (not a correctness check, per PLAN.md Phase 2):
# point poc's own Parser at every module making up poc's Phase 1/2 front
# end and driver, confirming it can at least parse its own source.
. ../../testenv.sh
SRC=../../../src
for f in "$SRC"/front/Diagnostics.Mod "$SRC"/front/Lexer.Mod \
         "$SRC"/front/SyntaxTree.Mod "$SRC"/front/SemanticActions.Mod \
         "$SRC"/front/Parser.Mod "$SRC"/driver/Poc.Mod
do
  echo "$(basename "$f"):"
  poc -check-syntax "$f"
done >result 2>&1
. ../../testresult.sh
