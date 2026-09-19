MODULE varParamGuard;
  (* Oberon2.pdf 8.1 / 8.2: a type guard, IS and WITH apply to "a variable
     parameter of record type" as well as to a pointer (PLAN.md Phase 9
     step 6). Every use below is accepted by real voc too (2026-09-19):
     IS, a guard as a designator's base, a guard passed on as a VAR
     argument, WITH - and, inside the WITH branch, a nested guard and IS on
     the narrowed parameter. A type-bound procedure's VAR receiver counts. *)
  TYPE
    Base = RECORD id: INTEGER END;
    Wide = RECORD (Base) extra: INTEGER END;
  VAR n: INTEGER;

  PROCEDURE Take(VAR x: Base): INTEGER;
  BEGIN RETURN x.id END Take;

  PROCEDURE Test(VAR x: Base);
  BEGIN
    IF x IS Wide THEN n := x(Wide).extra END;
    n := Take(x(Wide));
    WITH x: Wide DO
      IF x IS Wide THEN n := x(Wide).extra + x.extra END
    ELSE n := 0
    END
  END Test;

  PROCEDURE (VAR x: Base) Receiver();
  BEGIN
    IF x IS Wide THEN n := x(Wide).extra END
  END Receiver;

BEGIN
END varParamGuard.
