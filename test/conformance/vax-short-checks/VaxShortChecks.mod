MODULE VaxShortChecks;
  (* PLAN.md Phase 15 step 7b: with poc -range-checks, SHORT of a value
     that does not fit the narrower type traps, code 14, at SHORT's
     position, as on LLVM: CVTLW and CVTWB set V when it does not, and a
     HUGEINT fits a LONGINT when its high longword is its low one's sign
     (the design's section 9). *)

  PROCEDURE ShortL(l: LONGINT): INTEGER;
  BEGIN RETURN SHORT(l)
  END ShortL;

  PROCEDURE ShortI(i: INTEGER): SHORTINT;
  BEGIN RETURN SHORT(i)
  END ShortI;

  PROCEDURE ShortH(h: HUGEINT): LONGINT;
  BEGIN RETURN SHORT(h)
  END ShortH;

END VaxShortChecks.
