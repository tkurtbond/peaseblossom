MODULE finalize;
  (* PLAN.md Phase 12 step 5c: GarbageCollectedHeap.RegisterFinalizer.
     What is checked: an object dropped is finalized by the next
     collection (at least 8 of 10: the stack is scanned conservatively, so
     a stale word may keep one alive until the end); one still reachable
     is not; a finalizer that stores its object where it is reachable
     again revives it, intact, and is not called again; what a finalizable
     object points to survives for its finalizer, which may allocate and
     collect; a finalizer may register another; and at the end every
     object still registered is finalized, newest first, so summary's,
     registered first, runs last and counts all of them. *)
  IMPORT SYSTEM, Out, GarbageCollectedHeap;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node; value: LONGINT END;
  VAR
    kept, revived, summary, first, second: Node;
    dropped, droppedSum, revivals, keptCalls, chainValue, laterCalls: LONGINT;

  PROCEDURE New(value: LONGINT; next: Node): Node;
    VAR n: Node;
  BEGIN NEW(n); n.value := value; n.next := next; RETURN n
  END New;

  (* zeroes a stretch of stack, so that no dead frame there still holds a
     pointer to what was dropped *)
  PROCEDURE Scrub;
    VAR words: ARRAY 512 OF LONGINT;
  BEGIN words[0] := 0
  END Scrub;

  PROCEDURE Collect;
  BEGIN Scrub; GarbageCollectedHeap.Collect
  END Collect;

  (* allocates and drops n nodes *)
  PROCEDURE Churn(n: LONGINT);
    VAR k: LONGINT; garbage: Node;
  BEGIN FOR k := 1 TO n DO garbage := New(k, NIL) END
  END Churn;

  PROCEDURE CountDropped(obj: SYSTEM.PTR);
    VAR n: Node;
  BEGIN n := SYSTEM.VAL(Node, obj); INC(dropped); INC(droppedSum, n.value)
  END CountDropped;

  PROCEDURE CountKept(obj: SYSTEM.PTR);
  BEGIN INC(keptCalls)
  END CountKept;

  PROCEDURE Revive(obj: SYSTEM.PTR);
  BEGIN INC(revivals); revived := SYSTEM.VAL(Node, obj)
  END Revive;

  PROCEDURE Later(obj: SYSTEM.PTR);
  BEGIN INC(laterCalls)
  END Later;

  (* reads what its object points to after allocating enough to collect
     several times, then registers a finalizer for that *)
  PROCEDURE ReadChain(obj: SYSTEM.PTR);
    VAR n: Node;
  BEGIN
    n := SYSTEM.VAL(Node, obj);
    Churn(50000);
    chainValue := n.next.value;
    GarbageCollectedHeap.RegisterFinalizer(n.next, Later)
  END ReadChain;

  PROCEDURE Exiting(obj: SYSTEM.PTR);
    VAR n: Node;
  BEGIN
    n := SYSTEM.VAL(Node, obj);
    Out.String("at the end: "); Out.Int(n.value, 0); Out.Ln
  END Exiting;

  (* runs last: every other object registered has been finalized *)
  PROCEDURE Summary(obj: SYSTEM.PTR);
    VAR local, own: Node;
  BEGIN
    own := SYSTEM.VAL(Node, obj);
    local := New(31, NIL);
    Churn(50000); (* collections while the program ends *)
    Out.String("summary: dropped "); Out.Int(dropped, 0);
    Out.String(" sum "); Out.Int(droppedSum, 0);
    Out.String(", kept "); Out.Int(keptCalls, 0);
    Out.String(", later "); Out.Int(laterCalls, 0);
    Out.String(", local "); Out.Int(local.value, 0);
    Out.String(", own "); Out.Int(own.value, 0); Out.Ln
  END Summary;

  PROCEDURE DropTen;
    VAR k: LONGINT;
  BEGIN
    FOR k := 1 TO 10 DO GarbageCollectedHeap.RegisterFinalizer(New(k, NIL), CountDropped) END
  END DropTen;

  PROCEDURE DropRevivable;
  BEGIN GarbageCollectedHeap.RegisterFinalizer(New(55, New(56, NIL)), Revive)
  END DropRevivable;

  PROCEDURE DropChain;
  BEGIN GarbageCollectedHeap.RegisterFinalizer(New(1, New(77, NIL)), ReadChain)
  END DropChain;

BEGIN
  summary := New(99, NIL); GarbageCollectedHeap.RegisterFinalizer(summary, Summary);
  first := New(1, NIL); GarbageCollectedHeap.RegisterFinalizer(first, Exiting);
  kept := New(5, NIL); GarbageCollectedHeap.RegisterFinalizer(kept, CountKept);
  second := New(2, NIL); GarbageCollectedHeap.RegisterFinalizer(second, Exiting);

  DropTen; Collect;
  Out.String("dropped: ");
  IF dropped >= 8 THEN Out.String("at least 8") ELSE Out.Int(dropped, 0) END; Out.Ln;
  Out.String("kept: "); Out.Int(keptCalls, 0); Out.Int(kept.value, 2); Out.Ln;

  DropRevivable; Collect;
  Out.String("revived: "); Out.Int(revivals, 0);
  IF revived # NIL THEN Out.Int(revived.value, 3); Out.Int(revived.next.value, 3) END;
  Out.Ln;
  Churn(50000); Collect; Collect;
  Out.String("revived again: "); Out.Int(revivals, 0);
  Out.Int(revived.value, 3); Out.Int(revived.next.value, 3); Out.Ln;

  DropChain; Collect;
  Out.String("chain: "); Out.Int(chainValue, 0); Out.Ln;

  (* not finalized: a finalizer NIL, an object not on the heap *)
  GarbageCollectedHeap.RegisterFinalizer(New(3, NIL), NIL);
  GarbageCollectedHeap.RegisterFinalizer(SYSTEM.VAL(SYSTEM.PTR, SYSTEM.ADR(dropped)), Exiting);
  Out.String("end of body"); Out.Ln
END finalize.
