MODULE nilwith;
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
    i: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  n := NIL; i := 0;
  WITH n: Wide DO i := 1 ELSE i := 2 END;
  SysWrite(1, "B", 1)
END nilwith.
