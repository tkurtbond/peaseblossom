MODULE varguardfail;
  (* PLAN.md Phase 9 step 6: a guard on a VAR record parameter fails when
     the actual argument's own type is not the guard's. *)
  IMPORT Out;
  TYPE
    Base = RECORD id: INTEGER END;
    Wide = RECORD (Base) extra: INTEGER END;
  VAR b: Base; n: INTEGER;
  PROCEDURE Extra(VAR x: Base): INTEGER;
  BEGIN RETURN x(Wide).extra END Extra;
BEGIN
  Out.String("A");
  n := Extra(b);
  Out.String("B")
END varguardfail.
