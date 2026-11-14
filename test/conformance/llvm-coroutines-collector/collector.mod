MODULE collector;
  (* Each stack holds a list nothing else points to, in a suspended frame,
     while the other one allocates enough to collect several times. *)
  IMPORT Coroutines, GarbageCollectedHeap, Out;

  CONST length = 10000; churn = 500000;

  TYPE Node = POINTER TO RECORD next: Node; value: LONGINT; pad: ARRAY 6 OF LONGINT END;

  VAR main, worker: Coroutines.Coroutine;

  PROCEDURE Build(n, seed: LONGINT): Node;
    VAR list, x: Node; k: LONGINT;
  BEGIN
    list := NIL;
    FOR k := 1 TO n DO NEW(x); x.value := seed + k; x.next := list; list := x END;
    RETURN list
  END Build;

  PROCEDURE Check(list: Node; n, seed: LONGINT; who: ARRAY OF CHAR);
    VAR k, bad: LONGINT;
  BEGIN
    bad := 0; k := n;
    WHILE list # NIL DO
      IF list.value # seed + k THEN INC(bad) END;
      DEC(k); list := list.next
    END;
    Out.String(who); Out.String(": "); Out.Int(bad, 0); Out.String(" wrong, ");
    Out.Int(k, 0); Out.String(" missing"); Out.Ln
  END Check;

  (* allocates and drops, with the other stack's list reachable only from
     that stack; reports whether it collected more than twice *)
  PROCEDURE Churn(who: ARRAY OF CHAR);
    VAR k, before: LONGINT; x: Node;
  BEGIN
    before := GarbageCollectedHeap.CollectionCount();
    FOR k := 1 TO churn DO NEW(x); x.value := k END;
    Out.String(who); Out.String(" collected more than twice: ");
    IF GarbageCollectedHeap.CollectionCount() - before > 2 THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END Churn;

  PROCEDURE Work;
    VAR mine: Node;
  BEGIN
    mine := Build(length, 5000);
    Coroutines.Transfer(worker, main);
    Check(mine, length, 5000, "worker's list");
    Churn("worker");
    Coroutines.Transfer(worker, main);
    LOOP Coroutines.Transfer(worker, main) END
  END Work;

  PROCEDURE Run;
    VAR list: Node;
  BEGIN
    list := Build(length, 0);
    Coroutines.Init(Work, 65536, worker);
    Coroutines.Transfer(main, worker);
    Churn("main");
    Coroutines.Transfer(main, worker);
    Check(list, length, 0, "main's list")
  END Run;

BEGIN
  Run
END collector.
