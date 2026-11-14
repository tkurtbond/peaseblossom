MODULE traps;
  (* One trap of Tasks per run, chosen by the argument, with an object's
     finalizer registered, which every one of them runs: 19 (all tasks
     blocked), each case of 20 (misuse), and 17 (a call that blocks in a
     finalizer or a signal handler, with another task ready). *)
  IMPORT SYSTEM, Tasks, GarbageCollectedHeap, Modules, Platform, Out;

  TYPE
    Object = POINTER TO RECORD value: INTEGER END;
    Idle = POINTER TO RECORD (Tasks.TaskDesc) END;
    Receiver = POINTER TO RECORD (Tasks.TaskDesc) ch: Tasks.Channel END;
    Sender = POINTER TO RECORD (Tasks.TaskDesc) ch: Tasks.Channel END;
    Locker = POINTER TO RECORD (Tasks.TaskDesc) END;

  VAR
    which: LONGINT;
    kept: Object;
    ch: Tasks.Channel;
    lock: Tasks.Mutex;
    gate: Tasks.Condition;
    idle: Idle; receiver: Receiver; sender: Sender; locker: Locker;
    m: Tasks.Message;

  PROCEDURE ["C", "raise"] Raise(signal: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Finalize(obj: SYSTEM.PTR);
    VAR object: Object;
  BEGIN
    object := SYSTEM.VAL(Object, obj);
    Out.String("finalized "); Out.Int(object.value, 0); Out.Ln
  END Finalize;

  PROCEDURE FinalizeAndYield(obj: SYSTEM.PTR);
  BEGIN
    Out.String("a finalizer yields"); Out.Ln;
    Tasks.Yield
  END FinalizeAndYield;

  PROCEDURE Handler(signal: SYSTEM.INT32);
  BEGIN
    Out.String("a signal handler yields"); Out.Ln;
    Tasks.Yield
  END Handler;

  PROCEDURE (t: Idle) Run*;
  BEGIN
    Out.String("idle ran"); Out.Ln
  END Run;

  PROCEDURE (r: Receiver) Run*;
  BEGIN
    IF Tasks.Receive(r.ch, m) THEN END
  END Run;

  PROCEDURE (s: Sender) Run*;
  BEGIN
    Out.String("sender waits"); Out.Ln;
    Tasks.Send(s.ch, NIL);
    Out.String("not reached"); Out.Ln
  END Run;

  PROCEDURE (l: Locker) Run*;
  BEGIN
    Tasks.Lock(lock); Out.String("locker holds the mutex"); Out.Ln
  END Run;

  (* made here, not in the module body, so that no copy of its pointer is
     left in a frame the collector scans *)
  PROCEDURE DropFinalizedObject;
    VAR dropped: Object;
  BEGIN
    NEW(dropped); dropped.value := 2;
    GarbageCollectedHeap.RegisterFinalizer(dropped, FinalizeAndYield)
  END DropFinalizedObject;

BEGIN
  NEW(kept); kept.value := 1;
  GarbageCollectedHeap.RegisterFinalizer(kept, Finalize);
  Modules.GetIntArg(1, which);
  ch := Tasks.NewChannel(0);
  CASE which OF
  | 1: (* main alone waits *)
       IF Tasks.Receive(ch, m) THEN END
  | 2: (* main joins a task that waits on a channel no one sends on *)
       NEW(receiver); receiver.ch := ch; Tasks.Start(receiver, Tasks.DefaultStackSize);
       Tasks.Join(receiver)
  | 3: (* main waits for a mutex a finished task holds *)
       NEW(locker); Tasks.Start(locker, Tasks.DefaultStackSize); Tasks.Yield;
       Tasks.Lock(lock)
  | 4: (* main waits on a condition *)
       Tasks.Wait(gate)
  | 5: Tasks.Unlock(lock)
  | 6: NEW(locker); Tasks.Start(locker, Tasks.DefaultStackSize); Tasks.Yield;
       Tasks.Unlock(lock)
  | 7: Tasks.Join(Tasks.Current())
  | 8: Tasks.Close(ch); Tasks.Send(ch, NIL)
  | 9: (* a sender waiting when its channel is closed *)
       NEW(sender); sender.ch := ch; Tasks.Start(sender, Tasks.DefaultStackSize); Tasks.Yield;
       Tasks.Close(ch); Tasks.Yield
  | 10: Tasks.Close(ch); Tasks.Close(ch)
  | 11: NEW(idle); Tasks.Start(idle, Tasks.DefaultStackSize); Tasks.Start(idle, Tasks.DefaultStackSize)
  | 12: ch := Tasks.NewChannel(-1)
  | 13: NEW(idle); Tasks.Start(idle, Tasks.DefaultStackSize);
        DropFinalizedObject;
        GarbageCollectedHeap.Collect
  | 14: NEW(idle); Tasks.Start(idle, Tasks.DefaultStackSize);
        Platform.SetInterruptHandler(Handler);
        IF Raise(2) = 0 THEN END
  END;
  Out.String("not reached"); Out.Ln
END traps.
