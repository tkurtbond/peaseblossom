MODULE CoroutineTraps;
  (* On VAX/VMS (doc/developer/coroutines.md, Phase 4), llvm-coroutines-traps'
     program: one trap on or around a coroutine per run, chosen by the
     argument, with an object's finalizer registered, which every one of
     them runs. A Transfer in an AST stands for the one in a signal
     handler (7); and two cases more: Init without Free until VMS refuses
     a stack (13), and a recursion that runs into the guard page (14). *)
  IMPORT SYSTEM, AsynchronousTraps, Coroutines, GarbageCollectedHeap, Modules, Out;

  TYPE Object = POINTER TO RECORD value: INTEGER END;

  VAR
    main, worker, never, freed: Coroutines.Coroutine;
    which, made: LONGINT;
    kept: Object;
    nothing: Object;
    nobody: Coroutines.Body;

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

  PROCEDURE Routine(parameter: SYSTEM.CARD32);
  BEGIN
    Coroutines.Transfer(main, worker)
  END Routine;

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

  PROCEDURE Depth(n: LONGINT): LONGINT;
    VAR filler: ARRAY 64 OF CHAR;
  BEGIN
    filler[0] := CHR(n MOD 26 + ORD("a"));
    RETURN Depth(n + 1) + ORD(filler[0])
  END Depth;

  PROCEDURE Overflows;
  BEGIN
    Out.String("a coroutine recurses without end"); Out.Ln;
    Out.Int(Depth(0), 0)
  END Overflows;

  (* The object to be finalized is made here, not in the module body, so
     that no copy of its pointer is left in a frame the collector scans. *)
  PROCEDURE DropFinalizedObject;
    VAR dropped: Object;
  BEGIN
    NEW(dropped); dropped.value := 2;
    GarbageCollectedHeap.RegisterFinalizer(dropped, FinalizeAndTransfer)
  END DropFinalizedObject;

  (* Zeroes stack below the caller's frame, where DropFinalizedObject's
     copies of the pointer may be left, as poc zeroes every local *)
  PROCEDURE Scrub;
    VAR area: ARRAY 256 OF LONGINT;
  BEGIN
    area[0] := 0
  END Scrub;

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
       DropFinalizedObject; Scrub;
       GarbageCollectedHeap.Collect
  | 7: Coroutines.Init(Parked, 0, worker);
       IF AsynchronousTraps.Declare(Routine, 0) MOD 2 = 1 THEN END
  | 8: Coroutines.Init(Parked, MAX(LONGINT), worker)
  | 9: Start(Dereferences)
  | 10: Start(Halts)
  | 11: Start(Asserts)
  | 12: Start(nobody)
  | 13: Out.String("stacks of 1 MiB, none freed"); Out.Ln;
        LOOP Coroutines.Init(Parked, 1048576, worker); INC(made) END
  | 14: Start(Overflows)
  END;
  Out.String("not reached"); Out.Ln
END CoroutineTraps.
