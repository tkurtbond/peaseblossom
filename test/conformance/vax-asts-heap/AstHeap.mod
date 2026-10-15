MODULE AstHeap;
  (* Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
     proposals 2 and 8): a timer AST every 10 ms builds a batch of nodes
     with NEW and hangs it on a list, while the main line allocates lists
     of its own, so that collections run, and takes the batches, with
     ASTs disabled, and checks every node. The heap disables ASTs while it
     works, since this program imports AsynchronousTraps; without that an
     AST's NEW can find the heap halfway changed. *)
  IMPORT SYSTEM, Out, AsynchronousTraps, GarbageCollectedHeap;

  CONST
    batchNodes = 16;
    wanted = 200; (* batches checked before the end *)
    ownNodes = 500;
    tick = -100000; (* 10 ms, as a delta time in 100-ns units *)

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: LONGINT; next: Node END;
    Batch = POINTER TO BatchDesc;
    BatchDesc = RECORD number, sum: LONGINT; first: Node; next: Batch END;

  VAR
    incoming: Batch; (* the AST's, taken by the main line with ASTs disabled *)
    made: LONGINT; (* batches the AST has made *)
    stop: BOOLEAN;
    status: SYSTEM.INT32;
    taken, batch: Batch;
    own, node: Node;
    checked, badBatches, badOwn, passes, collectionsBefore, i, count, sum: LONGINT;
    wasEnabled: BOOLEAN;

  PROCEDURE ["VMS", "SYS$SETIMR"] SetTimer(eventFlag: SYSTEM.INT32; time-: HUGEINT;
                                           routine: AsynchronousTraps.Routine;
                                           parameter: SYSTEM.CARD32; flags: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$CANTIM"] CancelTimer(request: SYSTEM.CARD32; mode: SYSTEM.INT32): SYSTEM.INT32;

  (* the AST routine: a batch of nodes, hung on incoming, and the timer
     set again *)
  PROCEDURE Tick(parameter: SYSTEM.CARD32);
    VAR b: Batch; n: Node; k, s: LONGINT; result: SYSTEM.INT32;
  BEGIN
    IF ~stop THEN
      NEW(b); b.number := made; s := 0;
      FOR k := 1 TO batchNodes DO
        NEW(n); n.value := made * 1000 + k; s := s + n.value;
        n.next := b.first; b.first := n
      END;
      b.sum := s; b.next := incoming; incoming := b; INC(made);
      result := SetTimer(0, tick, Tick, 0, 0)
    END
  END Tick;

BEGIN
  collectionsBefore := GarbageCollectedHeap.CollectionCount();
  status := SetTimer(0, tick, Tick, 0, 0);
  WHILE checked < wanted DO
    own := NIL;
    FOR i := 1 TO ownNodes DO NEW(node); node.value := i; node.next := own; own := node END;
    sum := 0; count := 0; node := own;
    WHILE node # NIL DO sum := sum + node.value; INC(count); node := node.next END;
    IF (count # ownNodes) OR (sum # ownNodes * (ownNodes + 1) DIV 2) THEN INC(badOwn) END;
    wasEnabled := AsynchronousTraps.Disable();
    taken := incoming; incoming := NIL;
    AsynchronousTraps.Restore(wasEnabled);
    WHILE taken # NIL DO
      batch := taken; taken := taken.next;
      sum := 0; count := 0; node := batch.first;
      WHILE node # NIL DO
        IF node.value DIV 1000 # batch.number THEN INC(badBatches) END;
        sum := sum + node.value; INC(count); node := node.next
      END;
      IF (count # batchNodes) OR (sum # batch.sum) THEN INC(badBatches) END;
      INC(checked)
    END;
    INC(passes)
  END;
  stop := TRUE;
  status := CancelTimer(0, 0);
  Out.String("batches checked: ");
  IF checked >= wanted THEN Out.Int(wanted, 0); Out.String(" or more") ELSE Out.Int(checked, 0) END; Out.Ln;
  Out.String("bad batches: "); Out.Int(badBatches, 0); Out.Ln;
  Out.String("bad lists of the main line: "); Out.Int(badOwn, 0); Out.Ln;
  Out.String("collections during the run: ");
  (* how many depends on how the timer falls among the main line's NEWs
     (4 to 6 seen); enough to show collections while ASTs allocate *)
  IF GarbageCollectedHeap.CollectionCount() - collectionsBefore >= 3 THEN Out.String("3 or more")
  ELSE Out.Int(GarbageCollectedHeap.CollectionCount() - collectionsBefore, 0)
  END;
  Out.Ln
END AstHeap.
