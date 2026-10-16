MODULE valexternal;
  (* PLAN.md, "Ongoing language enhancements", item 3: an external
     procedure's name may stand only as x in SYSTEM.VAL(SYSTEM.ADDRESS, x);
     everywhere else it is refused, as before *)
  IMPORT SYSTEM;

  TYPE
    Absolute = PROCEDURE (x: SYSTEM.INT32): SYSTEM.INT32;
    Object = POINTER TO ObjectDesc;
    ObjectDesc = RECORD END;

  VAR
    f: Absolute;
    a: SYSTEM.ADDRESS;
    n: SYSTEM.INT32;
    o: Object;

  PROCEDURE ["C", "abs"] CAbs(x: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE (o: Object) Method; END Method;

  PROCEDURE Take(g: Absolute); END Take;

  PROCEDURE Give(): Absolute;
  BEGIN RETURN CAbs (* returned *)
  END Give;

  PROCEDURE Outer;
    PROCEDURE Inner; END Inner;
  BEGIN
    a := SYSTEM.VAL(SYSTEM.ADDRESS, Inner) (* nested, still refused *)
  END Outer;

BEGIN
  a := SYSTEM.VAL(SYSTEM.ADDRESS, CAbs); (* allowed *)
  f := SYSTEM.VAL(Absolute, CAbs); (* to a procedure type *)
  n := SYSTEM.VAL(SYSTEM.INT32, CAbs); (* to another integer type *)
  f := CAbs; (* assigned *)
  Take(CAbs); (* passed *)
  a := SYSTEM.VAL(SYSTEM.ADDRESS, o.Method) (* type-bound, still refused *)
END valexternal.
