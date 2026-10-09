MODULE VaxRangeChecks;
  (* PLAN.md Phase 15 step 7: with poc -range-checks, CHR of a value
     outside 0..255 traps, code 14, at CHR's position, as on LLVM: a
     SHORTINT when it is negative, a wider integer by an unsigned compare
     with 255, which a negative one fails too, and a HUGEINT also when its
     high longword is not zero (the design's section 9). *)

  PROCEDURE ChrB(x: SHORTINT): CHAR;
  BEGIN RETURN CHR(x)
  END ChrB;

  PROCEDURE ChrW(x: INTEGER): CHAR;
  BEGIN RETURN CHR(x)
  END ChrW;

  PROCEDURE ChrQ(x: HUGEINT): CHAR;
  BEGIN RETURN CHR(x)
  END ChrQ;

END VaxRangeChecks.
