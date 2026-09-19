MODULE nilguard;
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
  VAR
    n: Node;
    w: Wide;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  n := NIL; w := n(Wide);
  SysWrite(1, "B", 1)
END nilguard.
