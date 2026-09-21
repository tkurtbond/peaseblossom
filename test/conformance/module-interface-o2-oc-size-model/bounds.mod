MODULE bounds;
  (* PLAN.md's "Open design questions" (MAX(LONGINT)-in-CONST): Poc.Mod's
     -O2/-OC flags select the elementary-type size model
     MAX(T)/MIN(T)/SIZE(T) fold against (ConstantEvaluator.SetSizeModel).
     -check alone cannot observe this: MAX/MIN(T) always folds to type T
     itself regardless of the actual numeric bound picked, so an
     assignment to a T-typed variable type-checks under either model
     (Types.AssignmentCompatible compares types, not magnitudes). This
     test instead exports every bound via -emit-interface and diffs the
     printed decimal text between an -O2 and an -OC run (test.sh) -
     confirmed against real voc (2026-09-17): under -O2, SHORTINT/
     INTEGER/LONGINT/SET are 1/2/4/4 bytes; under -OC, 2/4/8/4 (voc gives
     -OC a 32-bit SET too: OPM.Mod, and its usage text).
     Deliberately excludes MIN(LONGINT)/MIN(HUGEINT): both hit a
     separate, pre-existing, undocumented-until-now ModuleInterface.
     FormatInt bug (see PLAN.md) that silently prints "-" with no digits
     for a value at exactly a LONGINT's two's-complement minimum - not
     what this test is checking. *)

  CONST
    MaxShort* = MAX(SHORTINT); MinShort* = MIN(SHORTINT);
    MaxInt* = MAX(INTEGER); MinInt* = MIN(INTEGER);
    MaxLong* = MAX(LONGINT);
    MaxSet* = MAX(SET);
    ShortSize* = SIZE(SHORTINT); IntSize* = SIZE(INTEGER);
    LongSize* = SIZE(LONGINT); SetSize* = SIZE(SET);
END bounds.
