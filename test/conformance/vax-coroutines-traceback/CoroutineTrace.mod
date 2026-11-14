MODULE CoroutineTrace;
  (* On VAX/VMS (doc/developer/coroutines.md, Phase 4): an access
     violation three routines deep on a coroutine, whose traceback lists
     them, then Coroutines' Start, and ends at POC_COROUTINE_START, the
     first frame of the coroutine's stack (CoroutineSwitch.mar). *)
  IMPORT SYSTEM, Coroutines, Out;

  VAR main, worker: Coroutines.Coroutine;

  PROCEDURE Inner;
  BEGIN
    Out.String("Inner writes to address 0"); Out.Ln;
    SYSTEM.PUT(0, 1)
  END Inner;

  PROCEDURE Middle;
  BEGIN
    Inner
  END Middle;

  PROCEDURE Body;
  BEGIN
    Out.String("the body runs"); Out.Ln;
    Coroutines.Transfer(worker, main);
    Middle
  END Body;

BEGIN
  Coroutines.Init(Body, Coroutines.DefaultStackSize, worker);
  Coroutines.Transfer(main, worker);
  Out.String("main resumes the body"); Out.Ln;
  Coroutines.Transfer(main, worker);
  Out.String("not reached"); Out.Ln
END CoroutineTrace.
