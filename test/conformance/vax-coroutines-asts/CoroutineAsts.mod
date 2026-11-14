MODULE CoroutineAsts;
  (* Coroutines on VAX/VMS (doc/developer/coroutines.md, Phase 4): a timer
     AST every 10 ms builds a batch of nodes with NEW, on whichever stack
     it interrupts, while two coroutines and the main program take turns,
     A, B, main, A, ...: each coroutine adds 50 nodes to a list held only
     in its own body's local variable, so only on its own stack, and checks
     the list when it reaches 500; the main program takes the AST's
     batches, with ASTs disabled, and checks every node. Collections run on
     every stack and in the ASTs, so a list or batch that a collection did
     not find through a suspended stack, or an AST's collection between a
     Transfer's change of the stack base and its switch, shows as a bad
     list. The program imports AsynchronousTraps, so the heap and Transfer
     disable ASTs while they work (AstHeap.mod, vax-asts-heap). *)
  IMPORT SYSTEM, Out, AsynchronousTraps, GarbageCollectedHeap, Coroutines;

  CONST
    batchNodes = 16;
    wanted = 200; (* batches checked before the end *)
    ownNodes = 500;
    step = 50; (* a coroutine's nodes between Transfers *)
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
    node: Node;
    checked, badBatches, badLists, lists, collectionsBefore, count, sum: LONGINT;
    wasEnabled: BOOLEAN;
    (* the main program, A and B, each resuming the next *)
    coroutines: ARRAY 3 OF Coroutines.Coroutine;

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

  (* coroutine which's body: lists of ownNodes nodes, step at a time *)
  PROCEDURE Work(which: INTEGER);
    VAR list, n: Node; i, k, c, s: LONGINT;
  BEGIN
    LOOP
      list := NIL; i := 0;
      WHILE i < ownNodes DO
        FOR k := 1 TO step DO INC(i); NEW(n); n.value := which * 100000 + i; n.next := list; list := n END;
        Coroutines.Transfer(coroutines[which], coroutines[(which + 1) MOD 3])
      END;
      c := 0; s := 0; n := list;
      WHILE n # NIL DO
        IF n.value DIV 100000 # which THEN INC(badLists) END;
        s := s + n.value MOD 100000; INC(c); n := n.next
      END;
      IF (c # ownNodes) OR (s # ownNodes * (ownNodes + 1) DIV 2) THEN INC(badLists) END;
      INC(lists)
    END
  END Work;

  PROCEDURE A;
  BEGIN
    Work(1)
  END A;

  PROCEDURE B;
  BEGIN
    Work(2)
  END B;

BEGIN
  Coroutines.Init(A, Coroutines.DefaultStackSize, coroutines[1]);
  Coroutines.Init(B, Coroutines.DefaultStackSize, coroutines[2]);
  collectionsBefore := GarbageCollectedHeap.CollectionCount();
  status := SetTimer(0, tick, Tick, 0, 0);
  WHILE checked < wanted DO
    Coroutines.Transfer(coroutines[0], coroutines[1]);
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
    END
  END;
  stop := TRUE;
  status := CancelTimer(0, 0);
  Out.String("batches checked: ");
  IF checked >= wanted THEN Out.Int(wanted, 0); Out.String(" or more") ELSE Out.Int(checked, 0) END; Out.Ln;
  Out.String("bad batches: "); Out.Int(badBatches, 0); Out.Ln;
  Out.String("bad lists of the coroutines: "); Out.Int(badLists, 0); Out.Ln;
  Out.String("lists checked: ");
  IF lists >= 10 THEN Out.String("10 or more") ELSE Out.Int(lists, 0) END; Out.Ln;
  Out.String("collections during the run: ");
  IF GarbageCollectedHeap.CollectionCount() - collectionsBefore >= 3 THEN Out.String("3 or more")
  ELSE Out.Int(GarbageCollectedHeap.CollectionCount() - collectionsBefore, 0)
  END;
  Out.Ln
END CoroutineAsts.
