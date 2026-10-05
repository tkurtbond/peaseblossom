MODULE nestedir;
  (* Golden IR of the nested-procedure lowering (doc/developer/nested-procedures.md): the
     hidden trailing parameters, in the analysis's order - a plain variable's
     address, a VAR record's address and type tag, an open array's address and
     lengths - the symbol of a nested function, a call from the enclosing
     procedure and one between siblings passing them on. *)
  TYPE
    Rec = RECORD n: INTEGER END;

  PROCEDURE Outer*(VAR r: Rec; VAR a: ARRAY OF INTEGER): INTEGER;
    VAR total: INTEGER;
    PROCEDURE Add(k: INTEGER);
    BEGIN total := total + k + r.n + SHORT(LEN(a))
    END Add;
    PROCEDURE Twice(k: INTEGER);
    BEGIN Add(k); Add(k)
    END Twice;
  BEGIN
    total := 0; Twice(1);
    RETURN total
  END Outer;

END nestedir.
