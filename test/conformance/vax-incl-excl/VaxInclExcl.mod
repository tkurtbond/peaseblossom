MODULE VaxInclExcl;
  (* PLAN.md Phase 15 step 7b: INCL(v, x) and EXCL(v, x), v := v + {x}
     and v - {x}, in place (the design's section 8): BISL2 or BICL2 of x's
     mask, a constant's, or ASHL x, #1's, as a set constructor's element,
     so that an x outside 0..31 leaves v as it was. *)

  VAR s: SET; sets: ARRAY 3 OF SET;

  PROCEDURE Include(VAR v: SET; x: INTEGER);
  BEGIN INCL(v, x)
  END Include;

  PROCEDURE Exclude(VAR v: SET; x: INTEGER);
  BEGIN EXCL(v, x)
  END Exclude;

  PROCEDURE IncludeHuge(VAR v: SET; x: HUGEINT);
  BEGIN INCL(v, x)
  END IncludeHuge;

  PROCEDURE Constants;
  BEGIN INCL(s, 0); INCL(s, 31); EXCL(s, 0)
  END Constants;

  PROCEDURE Element(k: INTEGER; x: SHORTINT);
  BEGIN INCL(sets[k], x)
  END Element;

  PROCEDURE Local(x: INTEGER): SET;
    VAR t: SET;
  BEGIN t := {1}; INCL(t, x); EXCL(t, 1); RETURN t
  END Local;

END VaxInclExcl.
