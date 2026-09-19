MODULE heapnil;
  (* PLAN.md Phase 9 step 5: the other half of heapfull - a program that
     does look at what NEW gave it sees NIL once the heap's ceiling is
     reached, and carries on (voc's behaviour). Prints "A", allocates
     until NEW answers NIL, prints "N" if the chain it built is intact
     and "B" at the end. *)
  IMPORT GarbageCollectedHeap;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: INTEGER
    END;
  VAR
    keep, n: Node;
    count: LONGINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  GarbageCollectedHeap.SetHeapLimit(300000);
  SysWrite(1, "A", 1);
  count := 0;
  LOOP
    NEW(n);
    IF n = NIL THEN EXIT END;
    n.next := keep; keep := n; INC(count)
  END;
  n := keep; 
  WHILE n # NIL DO DEC(count); n := n.next END;
  IF count = 0 THEN SysWrite(1, "N", 1) END;
  SysWrite(1, "B", 1)
END heapnil.
