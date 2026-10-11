MODULE heapfull;
  (* PLAN.md Phase 9 step 5: as in voc, NEW does not trap when the heap
     cannot satisfy it - the pointer is left NIL, and a program that
     ignores that is stopped by the NIL check on its first use. Prints
     "A", keeps allocating with every block still reachable (so no
     collection can help) until the ceiling stops it, then uses the NIL
     it got; must trap before "B". *)
  IMPORT GarbageCollectedHeap, Out;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: INTEGER
    END;
  VAR
    keep, n: Node;
BEGIN
  GarbageCollectedHeap.SetHeapLimit(300000);
  Out.String("A");
  LOOP
    NEW(n); n.next := keep; keep := n
  END;
  Out.String("B")
END heapfull.
