MODULE heapfull;
  (* PLAN.md Phase 9 step 5: NEW past the heap's ceiling, with every
     block still reachable so no collection can help, is a trap (the
     runtime's Allocate answers 0). Prints "A", keeps allocating, must
     stop with the diagnostic before "B". *)
  IMPORT GarbageCollectedHeap;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: INTEGER
    END;
  VAR
    keep, n: Node;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  GarbageCollectedHeap.SetHeapLimit(300000);
  SysWrite(1, "A", 1);
  LOOP
    NEW(n); n.next := keep; keep := n
  END;
  SysWrite(1, "B", 1)
END heapfull.
