MODULE HeapCeiling;

  (* PLAN.md Phase 16 step 4, on VAX/VMS only: the collector's own
     ceiling, three quarters of the paging file quota left when it
     starts, stops the heap before VMS refuses it memory. A list is grown
     until NEW gives NIL; the heap then holds more than half of what was
     left and no more than three quarters. *)

  IMPORT SYSTEM, Out, GarbageCollectedHeap;

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node; pad: ARRAY 4000 OF CHAR END;

  VAR head, p: Node; left: SYSTEM.ADDRESS;

  PROCEDURE ["VMS", "POC_PAGE_FILE_LEFT"] PageFileLeft(): SYSTEM.ADDRESS;

  PROCEDURE YesNo(text: ARRAY OF CHAR; b: BOOLEAN);
  BEGIN
    Out.String(text);
    IF b THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END YesNo;

BEGIN
  left := PageFileLeft();
  REPEAT NEW(p); IF p # NIL THEN p.next := head; head := p END UNTIL p = NIL;
  YesNo("NEW gave NIL: ", head # NIL);
  YesNo("the heap holds more than half the quota left: ",
    GarbageCollectedHeap.HeapBytes() > left DIV 2);
  YesNo("and no more than three quarters: ", GarbageCollectedHeap.HeapBytes() <= left DIV 4 * 3)
END HeapCeiling.
