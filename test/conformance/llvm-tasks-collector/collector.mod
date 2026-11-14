MODULE collector;
  (* Tasks and the collector (doc/developer/tasks.md, Phase 9): lists held
     only in a channel that only a blocked task's stack points to, in a
     message a blocked sender holds, and on the stacks of tasks that only
     Tasks' queues point to, survive the collections main causes. *)
  IMPORT Tasks, GarbageCollectedHeap, Out;

  CONST length = 2000; lists = 20; churn = 500000;

  TYPE
    Node = POINTER TO RECORD next: Node; value: LONGINT; pad: ARRAY 6 OF LONGINT END;
    List = POINTER TO RECORD (Tasks.MessageDesc) first: Node; seed: LONGINT END;
    Holder = POINTER TO RECORD (Tasks.TaskDesc) END;
    Sender = POINTER TO RECORD (Tasks.TaskDesc) seed: LONGINT END;
    Keeper = POINTER TO RECORD (Tasks.TaskDesc) seed: LONGINT END;

  VAR
    wake, delivery, results: Tasks.Channel;
    gate: Tasks.Condition;
    open: BOOLEAN;
    holder: Holder;
    m: Tasks.Message;
    k: LONGINT;

  PROCEDURE Build(n, seed: LONGINT): List;
    VAR list: List; x: Node; k: LONGINT;
  BEGIN
    NEW(list); list.seed := seed;
    FOR k := 1 TO n DO NEW(x); x.value := seed + k; x.next := list.first; list.first := x END;
    RETURN list
  END Build;

  (* the number of nodes wrong or missing *)
  PROCEDURE Damage(list: List): LONGINT;
    VAR k, bad: LONGINT; x: Node;
  BEGIN
    bad := 0; k := length; x := list.first;
    WHILE x # NIL DO
      IF x.value # list.seed + k THEN INC(bad) END;
      DEC(k); x := x.next
    END;
    RETURN bad + ABS(k)
  END Damage;

  PROCEDURE Report(who: ARRAY OF CHAR; bad: LONGINT);
  BEGIN
    Out.String(who); Out.String(": "); Out.Int(bad, 0); Out.String(" damaged"); Out.Ln
  END Report;

  PROCEDURE Churn;
    VAR k, before: LONGINT; x: Node;
  BEGIN
    before := GarbageCollectedHeap.CollectionCount();
    FOR k := 1 TO churn DO NEW(x); x.value := k END;
    Out.String("main collected more than twice: ");
    IF GarbageCollectedHeap.CollectionCount() - before > 2 THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END Churn;

  (* fills a channel only its stack points to, then waits *)
  PROCEDURE (h: Holder) Run*;
    VAR mine: Tasks.Channel; k, bad: LONGINT; m: Tasks.Message;
  BEGIN
    mine := Tasks.NewChannel(lists);
    FOR k := 1 TO lists DO Tasks.Send(mine, Build(length, k * 10000)) END;
    Tasks.Close(mine);
    IF Tasks.Receive(wake, m) THEN END;
    bad := 0; k := 0;
    WHILE Tasks.Receive(mine, m) DO bad := bad + Damage(m(List)); INC(k) END;
    Report("the held channel's lists", bad + ABS(k - lists))
  END Run;

  (* waits in Send with a list only its waiter and its stack point to *)
  PROCEDURE (s: Sender) Run*;
  BEGIN
    Tasks.Send(delivery, Build(length, s.seed))
  END Run;

  (* keeps a list in a local, waiting on a condition; only Tasks' queues
     point to the task *)
  PROCEDURE (t: Keeper) Run*;
    VAR list: List; result: List;
  BEGIN
    list := Build(length, t.seed);
    WHILE ~open DO Tasks.Wait(gate) END;
    NEW(result); result.seed := Damage(list);
    Tasks.Send(results, result)
  END Run;

  PROCEDURE StartAnonymous;
    VAR s: Sender; t: Keeper; k: LONGINT;
  BEGIN
    FOR k := 1 TO 5 DO
      NEW(s); s.seed := 500000 + k * 10000; Tasks.Start(s, Tasks.DefaultStackSize);
      NEW(t); t.seed := 900000 + k * 10000; Tasks.Start(t, Tasks.DefaultStackSize)
    END
  END StartAnonymous;

  PROCEDURE Run;
    VAR bad, count: LONGINT;
  BEGIN
    wake := Tasks.NewChannel(0); delivery := Tasks.NewChannel(0); results := Tasks.NewChannel(5);
    NEW(holder); Tasks.Start(holder, Tasks.DefaultStackSize);
    StartAnonymous;
    Tasks.Yield;   (* every task runs until it waits *)
    Churn;
    Tasks.Yield;
    Churn;
    bad := 0; count := 0;
    WHILE count < 5 DO
      IF Tasks.Receive(delivery, m) THEN bad := bad + Damage(m(List)); INC(count) END
    END;
    Report("the waiting senders' lists", bad);
    Churn;
    open := TRUE; Tasks.Broadcast(gate);
    bad := 0;
    FOR count := 1 TO 5 DO
      IF Tasks.Receive(results, m) THEN bad := bad + m(List).seed END
    END;
    Report("the keepers' lists", bad);
    Tasks.Send(wake, NIL);
    Tasks.Join(holder)
  END Run;

BEGIN
  Run
END collector.
