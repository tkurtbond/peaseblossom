MODULE ptrir;
  (* PLAN.md Phase 9 step 5: golden IR for the pointer constructs - NEW of
     a record and of an array holding pointers (whose descriptor is
     synthesized), NIL checks before "." "[" and "^", an inherited field,
     IS, a type guard, WITH, a short-circuited "&" and a pointer-holding
     local. Only this module's own part of the program is kept in the
     golden (see test.sh); the runtime modules NEW pulls in are not. *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: INTEGER
    END;
    Wide = POINTER TO WideDesc;
    WideDesc = RECORD (NodeDesc)
      extra: INTEGER
    END;
    Table = POINTER TO ARRAY 4 OF Node;
    Bytes = POINTER TO ARRAY 8 OF CHAR;
  VAR
    head: Node;
    table: Table;
    bytes: Bytes;

  PROCEDURE Fill(n: Node; w: Wide): INTEGER;
    VAR local: Node; result: INTEGER;
  BEGIN
    local := n.next;
    NEW(w); w.extra := 1; w.value := 2;
    n^ := w^;
    result := 0;
    IF (n # NIL) & (n.value = 2) THEN result := 1 END;
    IF n IS Wide THEN result := result + n(Wide).extra END;
    WITH n: Wide DO result := result + n.extra END;
    RETURN result
  END Fill;

BEGIN
  NEW(head); NEW(table); NEW(bytes);
  table[1] := head; bytes[0] := "x"; head := NIL
END ptrir.
