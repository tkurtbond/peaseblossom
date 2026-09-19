MODULE heapfull;
  (* PLAN.md Phase 9 step 5: as in voc, NEW does not trap when the heap
     cannot satisfy it - the pointer is left NIL, and a program that
     ignores that is stopped by the NIL check on its first use. Prints
     "A", keeps allocating with every block still reachable (so no
     collection can help) until the ceiling stops it, then uses the NIL
     it got; must trap before "B". *)
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
