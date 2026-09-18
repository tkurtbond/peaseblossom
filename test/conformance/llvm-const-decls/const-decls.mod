MODULE constDecls;
  (* PLAN.md Phase 8 step 13: fixture promotion - the compile+link+run+
     diff-stdout half of semantic-const-decls's own CONST coverage,
     trimmed to exactly the subset LLVMCodeGenerator.Mod's own codegen
     actually supports. GenerateConstValue only handles obj.value.kind
     of intValue/charValue/boolValue/setValue - realValue and
     stringValue both hit its own "Unsupported" path (PLAN.md Phase 8
     step 5 scope), so pi/widened/half (REAL) and greeting (a named
     STRING CONST, not a literal passed directly to a call) are all
     dropped. SET *constructors* like "{1, 2, 5..8}" separately hit
     GenerateSetExpr's own "SET constructors / NIL" Unsupported path,
     so aSet/combinedSet/isMember are dropped too. What remains -
     INTEGER arithmetic (including DIV/MOD and a later constant
     referencing an earlier one), BOOLEAN & / OR / ~ over TRUE/FALSE,
     and a hex CHAR literal - is genuinely codegen-supported and not
     yet exercised at runtime by any earlier Phase 8 fixture (every
     earlier one prints a VAR-computed result, never a CONST-folded
     one). Runtime-observable via the same SysWrite/"OK"-vs-"FAIL"
     pattern every other Phase 8 runtime fixture uses (see
     llvm-multi-module/client.mod). See ../crosscheck for
     this same CONST-folding subset re-verified under voc/Console.Mod
     directly - genuinely practical here (PLAN.md step 13's own
     "cross-check ... where practical"), unlike every earlier Phase 8
     runtime fixture, because this one's own core logic needs no FFI at
     all - only the final OK/FAIL print does, and that's trivially
     swapped for Console.String there. *)
  CONST
    n = 10;
    limit = 100;
    quotient = 7 DIV 2;
    remainder = 7 MOD 2;
    flag = TRUE & ~FALSE;
    disjunction = FALSE OR (n < limit);
    letter = 41X; (* 'A' *)
    doubled = n * 2;
  VAR ok: BOOLEAN;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  ok := (quotient = 3) & (remainder = 1) & flag & disjunction & (ORD(letter) = 65) & (doubled = 20);
  IF ok THEN SysWrite(1, "OK", 2) ELSE SysWrite(1, "FAIL", 4) END
END constDecls.
