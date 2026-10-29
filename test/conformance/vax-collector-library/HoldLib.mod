MODULE HoldLib;
  (* a library's module that allocates, imported by a main module that
     calls no NEW itself *)
  TYPE
    Thing* = POINTER TO ThingRecord;
    ThingRecord = RECORD n*: LONGINT; next*: Thing END;

  PROCEDURE Make*(n: LONGINT; next: Thing): Thing;
    VAR t: Thing;
  BEGIN
    NEW(t); t.n := n; t.next := next;
    RETURN t
  END Make;

  (* count things made and dropped, each a garbage list of ten, which
     forces collections *)
  PROCEDURE Churn*(count: LONGINT);
    VAR i: LONGINT; garbage: Thing;
  BEGIN
    garbage := NIL;
    FOR i := 1 TO count DO
      garbage := Make(-1, garbage);
      IF i MOD 10 = 0 THEN garbage := NIL END
    END
  END Churn;
END HoldLib.
