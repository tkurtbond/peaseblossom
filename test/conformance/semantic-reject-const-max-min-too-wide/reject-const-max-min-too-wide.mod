MODULE rejectConstMaxMinTooWide;
  (* Companion to semantic-const-max-min-size: MIN(INTEGER) folds to
     Types.Integer (-32768), which SHORTINT's own range (-128..127) does
     not include - assignment-incompatible, same as any other type
     mismatch (Appendix A's assignment-compatible rule 2). Deliberately
     avoids arithmetic on a MAX/MIN(T) result (e.g. "MAX(SHORTINT) + 1"),
     which depends on a separate, pre-existing gap - ConstantEvaluator's
     arithmetic folding (Types.WiderOf-only) does not re-derive a
     computed constant's minimal type from its actual value the way a
     bare literal does, so such an expression stays SHORTINT-typed even
     when its value overflows (see PLAN.md's own open design question on
     this). This test instead checks MIN(T)/MAX(T) itself folds to
     exactly type T, not a narrower one, with no arithmetic involved.
     Confirmed against real voc (2026-09-17): rejects this exact module
     with "incompatible assignment". *)

  CONST TooWide = MIN(INTEGER);
  VAR s: SHORTINT;
BEGIN
  s := TooWide
END rejectConstMaxMinTooWide.
