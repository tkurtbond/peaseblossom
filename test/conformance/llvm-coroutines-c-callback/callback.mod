MODULE callback;
  (* A coroutine switches out of a C callback, and is resumed, and returns
     to C, before anything else uses that C code. A list reachable only
     from the C frame of the suspended stack survives the collections main
     causes meanwhile. The rounding mode one coroutine sets is not seen in
     the other. *)
  IMPORT SYSTEM, Callback, Coroutines, GarbageCollectedHeap, Out;

  CONST length = 10000; churn = 500000;

  TYPE Node = POINTER TO RECORD next: Node; value: LONGINT; pad: ARRAY 6 OF LONGINT END;

  VAR
    main, worker: Coroutines.Coroutine;
    make: Callback.Make; pause: Callback.Pause; check: Callback.Check;
    k, before: LONGINT; x: Node;

  PROCEDURE ShowRounding(who: ARRAY OF CHAR);
  BEGIN
    Out.String(who); Out.String(" rounds upward: ");
    IF Callback.RoundingUp() # 0 THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END ShowRounding;

  PROCEDURE Make(): SYSTEM.ADDRESS;
    VAR list, x: Node; k: LONGINT;
  BEGIN
    list := NIL;
    FOR k := 1 TO length DO NEW(x); x.value := k; x.next := list; list := x END;
    RETURN SYSTEM.VAL(SYSTEM.ADDRESS, list)
  END Make;

  PROCEDURE Pause;
  BEGIN
    Out.String("the callback switches out"); Out.Ln;
    Coroutines.Transfer(worker, main);
    Out.String("the callback is resumed"); Out.Ln
  END Pause;

  PROCEDURE Check(held: SYSTEM.ADDRESS);
    VAR list: Node; k, bad: LONGINT;
  BEGIN
    list := SYSTEM.VAL(Node, held);
    bad := 0; k := length;
    WHILE list # NIL DO
      IF list.value # k THEN INC(bad) END;
      DEC(k); list := list.next
    END;
    Out.String("the list C held: "); Out.Int(bad, 0); Out.String(" wrong, ");
    Out.Int(k, 0); Out.String(" missing"); Out.Ln
  END Check;

  PROCEDURE Work;
  BEGIN
    Callback.RoundUp;
    ShowRounding("the worker");
    Callback.Hold(make, pause, check);
    ShowRounding("the worker");
    LOOP Coroutines.Transfer(worker, main) END
  END Work;

BEGIN
  make := Make; pause := Pause; check := Check;
  Coroutines.Init(Work, Coroutines.DefaultStackSize, worker);
  Coroutines.Transfer(main, worker);
  ShowRounding("main");
  before := GarbageCollectedHeap.CollectionCount();
  FOR k := 1 TO churn DO NEW(x); x.value := k END;
  Out.String("main collected more than twice: ");
  IF GarbageCollectedHeap.CollectionCount() - before > 2 THEN Out.String("yes") ELSE Out.String("no") END;
  Out.Ln;
  Coroutines.Transfer(main, worker);
  ShowRounding("main")
END callback.
