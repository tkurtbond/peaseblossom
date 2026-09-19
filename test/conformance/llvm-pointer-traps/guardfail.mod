MODULE guardfail;
  (* PLAN.md Phase 9 step 5's pointer traps: prints "A", does the thing
     named in the file name, and must stop with the trap's diagnostic and
     exit status before printing "B" (see test.sh). *)
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
    n: Node;
    w: Wide;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

BEGIN
  SysWrite(1, "A", 1);
  NEW(n); w := n(Wide);
  SysWrite(1, "B", 1)
END guardfail.
