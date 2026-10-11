MODULE varwithnomatch;
  (* PLAN.md Phase 9 step 6: a WITH on a VAR record parameter with no
     matching branch and no ELSE aborts the program. *)
  IMPORT Out;
  TYPE
    Base = RECORD id: INTEGER END;
    Wide = RECORD (Base) extra: INTEGER END;
  VAR b: Base; n: INTEGER;
  PROCEDURE Extra(VAR x: Base): INTEGER;
    VAR result: INTEGER;
  BEGIN
    WITH x: Wide DO result := x.extra END;
    RETURN result
  END Extra;
BEGIN
  Out.String("A");
  n := Extra(b);
  Out.String("B")
END varwithnomatch.
