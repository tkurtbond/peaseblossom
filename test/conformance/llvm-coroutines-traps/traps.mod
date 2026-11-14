MODULE traps;
  (* One trap on or around a coroutine per run, chosen by the argument,
     with an object's finalizer registered, which every one of them runs. *)
  IMPORT SYSTEM, Coroutines, GarbageCollectedHeap, Modules, Platform, Out;

  TYPE Object = POINTER TO RECORD value: INTEGER END;

  VAR
    main, worker, never, freed: Coroutines.Coroutine;
    which: LONGINT;
    kept: Object;
    nothing: Object;
    nobody: Coroutines.Body;

  PROCEDURE ["C", "raise"] Raise(signal: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Finalize(obj: SYSTEM.PTR);
    VAR object: Object;
  BEGIN
    object := SYSTEM.VAL(Object, obj);
    Out.String("finalized "); Out.Int(object.value, 0); Out.Ln
  END Finalize;

  PROCEDURE FinalizeAndTransfer(obj: SYSTEM.PTR);
  BEGIN
    Out.String("a finalizer transfers"); Out.Ln;
    Coroutines.Transfer(main, worker)
  END FinalizeAndTransfer;

  PROCEDURE Handler(signal: SYSTEM.INT32);
  BEGIN
    Coroutines.Transfer(main, worker)
  END Handler;

  PROCEDURE Returns;
  BEGIN
    Out.String("a body returns"); Out.Ln
  END Returns;

  PROCEDURE Parked;
  BEGIN
    LOOP Coroutines.Transfer(worker, main) END
  END Parked;

  PROCEDURE FreesItself;
  BEGIN
    Coroutines.Free(worker)
  END FreesItself;

  PROCEDURE FreesMain;
  BEGIN
    Coroutines.Free(main)
  END FreesMain;

  PROCEDURE Dereferences;
  BEGIN
    Out.String("NIL dereferenced on a coroutine"); Out.Ln;
    nothing.value := 1
  END Dereferences;

  PROCEDURE Halts;
  BEGIN
    HALT(42)
  END Halts;

  PROCEDURE Asserts;
  BEGIN
    ASSERT(which = 0, 77)
  END Asserts;

  (* The object to be finalized is made here, not in the module body, so
     that no copy of its pointer is left in a frame the collector scans
     (i386 at -opt 0 keeps one). *)
  PROCEDURE DropFinalizedObject;
    VAR dropped: Object;
  BEGIN
    NEW(dropped); dropped.value := 2;
    GarbageCollectedHeap.RegisterFinalizer(dropped, FinalizeAndTransfer)
  END DropFinalizedObject;

  PROCEDURE Start(body: Coroutines.Body);
  BEGIN
    Coroutines.Init(body, Coroutines.DefaultStackSize, worker);
    Coroutines.Transfer(main, worker)
  END Start;

BEGIN
  NEW(kept); kept.value := 1;
  GarbageCollectedHeap.RegisterFinalizer(kept, Finalize);
  Modules.GetIntArg(1, which);
  CASE which OF
  | 1: Start(Returns)
  | 2: Coroutines.Transfer(main, never)
  | 3: Coroutines.Init(Parked, 0, freed); Coroutines.Free(freed);
       Coroutines.Transfer(main, freed)
  | 4: Start(FreesItself)
  | 5: Start(FreesMain)
  | 6: Coroutines.Init(Parked, 0, worker);
       DropFinalizedObject;
       GarbageCollectedHeap.Collect
  | 7: Coroutines.Init(Parked, 0, worker);
       Platform.SetInterruptHandler(Handler);
       IF Raise(2) = 0 THEN END
  | 8: Coroutines.Init(Parked, MAX(LONGINT), worker)
  | 9: Start(Dereferences)
  | 10: Start(Halts)
  | 11: Start(Asserts)
  | 12: Start(nobody)
  END;
  Out.String("not reached"); Out.Ln
END traps.
