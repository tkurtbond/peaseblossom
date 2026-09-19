MODULE varguardfail;
  (* PLAN.md Phase 9 step 6: a guard on a VAR record parameter fails when
     the actual argument's own type is not the guard's. *)
  TYPE
    Base = RECORD id: INTEGER END;
    Wide = RECORD (Base) extra: INTEGER END;
  VAR b: Base; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE Extra(VAR x: Base): INTEGER;
  BEGIN RETURN x(Wide).extra END Extra;
BEGIN
  SysWrite(1, "A", 1);
  n := Extra(b);
  SysWrite(1, "B", 1)
END varguardfail.
