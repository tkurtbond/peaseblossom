MODULE nilcaret;
  (* PLAN.md Phase 9 step 5's pointer traps: prints "A", does the thing
     named in the file name, and must stop with the trap's diagnostic and
     exit status before printing "B" (see test.sh). *)
  IMPORT Out;
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
    Vector = POINTER TO ARRAY 4 OF INTEGER;
  VAR
    p, q: Node;

BEGIN
  Out.String("A");
  NEW(q); p^ := q^;
  Out.String("B")
END nilcaret.
