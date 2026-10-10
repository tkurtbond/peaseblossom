MODULE CollectOut;

  (* PLAN.md Phase 16 step 4: rtl/vax's GarbageCollectedHeap, the same
     output from the LLVM backend's collector. Far more is allocated than
     the guest's paging file quota (5 MB) allows at once, while what a
     module variable, a local, an array of pointers and a list too deep
     for the mark stack hold must survive; finalizers run; and a heap
     ceiling makes NEW give NIL, after which, once the live data is
     dropped, it allocates again. *)

  IMPORT SYSTEM, Out, GarbageCollectedHeap;

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: LONGINT; next: Node; pad: ARRAY 100 OF CHAR END;
    Bytes = POINTER TO ARRAY OF CHAR;
    Nodes = POINTER TO ARRAY OF Node;

  VAR
    list, held: Node;
    table: Nodes;
    finalized: LONGINT;

  PROCEDURE Finalize(obj: SYSTEM.PTR);
  BEGIN
    INC(finalized)
  END Finalize;

  PROCEDURE Build(n: LONGINT): Node;
    VAR head, p: Node; i: LONGINT;
  BEGIN
    head := NIL;
    FOR i := 1 TO n DO NEW(p); p.value := i; p.next := head; head := p END;
    RETURN head
  END Build;

  PROCEDURE Sum(p: Node): LONGINT;
    VAR s: LONGINT;
  BEGIN
    s := 0;
    WHILE p # NIL DO s := s + p.value; p := p.next END;
    RETURN s
  END Sum;

  PROCEDURE Line(text: ARRAY OF CHAR; n: LONGINT);
  BEGIN
    Out.String(text); Out.Int(n, 0); Out.Ln
  END Line;

  PROCEDURE YesNo(text: ARRAY OF CHAR; b: BOOLEAN);
  BEGIN
    Out.String(text);
    IF b THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END YesNo;

  (* 40 MB of garbage, while local holds a list only this frame knows *)
  PROCEDURE Churn(rounds: LONGINT);
    VAR i: LONGINT; b: Bytes; local: Node;
  BEGIN
    local := Build(100);
    FOR i := 1 TO rounds DO NEW(b, 4000); b[0] := "x"; b[3999] := "y" END;
    Line("local list's sum: ", Sum(local))
  END Churn;

  (* ten objects with finalizers, unreachable once this returns *)
  PROCEDURE Garbage;
    VAR p: Node; i: LONGINT;
  BEGIN
    FOR i := 1 TO 10 DO NEW(p); GarbageCollectedHeap.RegisterFinalizer(p, Finalize) END
  END Garbage;

  PROCEDURE TableSum(): LONGINT;
    VAR i, s: LONGINT;
  BEGIN
    s := 0;
    FOR i := 0 TO LEN(table^) - 1 DO s := s + Sum(table[i]) END;
    RETURN s
  END TableSum;

  (* Under a ceiling of 1 MB more than the heap has, a list held by
     held, grown until NEW gives NIL: whether it did, and whether the
     list is whole. Done in a frame of its own, gone before held is
     dropped, since the stack is scanned conservatively: a pointer left
     in this frame, an argument list's say, would keep the list. *)
  PROCEDURE Fill(VAR gaveNil, whole: BOOLEAN);
    VAR p: Node; count: LONGINT;
  BEGIN
    GarbageCollectedHeap.SetHeapLimit(GarbageCollectedHeap.HeapBytes() + 1048576);
    held := NIL; count := 0;
    REPEAT
      NEW(p);
      IF p # NIL THEN p.value := 1; p.next := held; held := p; INC(count) END
    UNTIL p = NIL;
    gaveNil := count > 0;
    whole := Sum(held) = count
  END Fill;

  (* NEW gives NIL before the ceiling is passed, and allocates again once
     the list is dropped *)
  PROCEDURE Ceiling;
    VAR p: Node; gaveNil, whole: BOOLEAN;
  BEGIN
    Fill(gaveNil, whole);
    YesNo("NEW gave NIL under a ceiling: ", gaveNil);
    YesNo("the list it made is whole: ", whole);
    held := NIL;
    GarbageCollectedHeap.Collect;
    NEW(p);
    YesNo("NEW allocates once it is dropped: ", p # NIL)
  END Ceiling;

  PROCEDURE Run;
    VAR i: LONGINT;
  BEGIN
    (* a mark stack of four entries, overflowed by the table *)
    GarbageCollectedHeap.SetMarkStackCapacity(4);
    list := Build(1000);
    NEW(table, 50);
    FOR i := 0 TO 49 DO table[i] := Build(10) END;
    Garbage;
    Churn(10000);
    Line("module list's sum: ", Sum(list));
    Line("table's sum: ", TableSum());
    GarbageCollectedHeap.Collect;
    YesNo("collected: ", GarbageCollectedHeap.CollectionCount() > 1);
    Line("finalized: ", finalized);
    YesNo("heap under 2 MB: ", GarbageCollectedHeap.HeapBytes() < 2097152);
    Ceiling
  END Run;

BEGIN
  Run
END CollectOut.
