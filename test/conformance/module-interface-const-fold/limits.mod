MODULE limits;
  (* PLAN.md Phase 9 step 10: the .sym writer against the constants that
     step folds. A folded integer prints as its value (the reader re-types
     it by value, which is what folding does too); the largest finite REAL
     and LONGREAL, and their negations, cannot be printed as decimal text
     that ConstantEvaluator.ParseReal reads back exactly - its repeated
     multiplication by ten drifts - so they are printed as MAX(REAL) and
     friends, by value and type (ModuleInterface.ExtremeRealSpelling).
     Written under -O2 and again under -OC, where SHORTINT/INTEGER/LONGINT
     are wider and the same expression can land in a different type; and
     the interface is read back as source, which must reproduce itself
     byte for byte. *)

  CONST
    bigReal* = MAX(REAL);
    lowReal* = MIN(REAL);
    bigLongReal* = MAX(LONGREAL);
    lowLongReal* = -MAX(LONGREAL);
    total* = 2 * 100 + 2 * 10;
    negShort* = -128;
    beyondShort* = MAX(SHORTINT) + 1;
    shifted* = ASH(1, 20);
    hugeShift* = ASH(1, 40);
    wide* = 100000 * 100000;
    hidden = 3 * 7;
END limits.
