MODULE varwithnomatch;
  (* PLAN.md Phase 9 step 6: a WITH on a VAR record parameter with no
     matching branch and no ELSE aborts the program. *)
  TYPE
    Base = RECORD id: INTEGER END;
    Wide = RECORD (Base) extra: INTEGER END;
  VAR b: Base; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE Extra(VAR x: Base): INTEGER;
    VAR result: INTEGER;
  BEGIN
    WITH x: Wide DO result := x.extra END;
    RETURN result
  END Extra;
BEGIN
  SysWrite(1, "A", 1);
  n := Extra(b);
  SysWrite(1, "B", 1)
END varwithnomatch.
