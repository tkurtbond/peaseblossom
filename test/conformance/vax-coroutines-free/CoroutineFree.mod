MODULE CoroutineFree;
  (* On VAX/VMS (doc/developer/coroutines.md, Phase 4), llvm-coroutines-
     free's program: Free gives a stack back, so that 1000 coroutines of
     1 MiB each, run and freed one after another, fit in the page-file
     quota, where without Free some 150 would spend the 300000 pages the
     development system's accounts have. Free of a record
     never given to Init and a second Free do nothing; a Transfer to a
     freed coroutine through another copy of its record traps. *)
  IMPORT Coroutines, Out;

  CONST rounds = 1000; size = 1048576;

  VAR main, worker, copy, never: Coroutines.Coroutine; k, ran: LONGINT;

  PROCEDURE Work;
    VAR filler: ARRAY 1024 OF LONGINT; j: INTEGER;
  BEGIN
    FOR j := 0 TO LEN(filler) - 1 DO filler[j] := j END;
    ran := ran + filler[LEN(filler) - 1];
    LOOP Coroutines.Transfer(worker, main) END
  END Work;

BEGIN
  Coroutines.Free(never);
  Out.String("Free of a record never given to Init: nothing"); Out.Ln;
  FOR k := 1 TO rounds DO
    Coroutines.Init(Work, size, worker);
    Coroutines.Transfer(main, worker);
    Coroutines.Free(worker)
  END;
  Out.String("ran "); Out.Int(ran DIV 1023, 0); Out.String(" coroutines of 1 MiB"); Out.Ln;
  Coroutines.Init(Work, size, worker);
  copy := worker;
  Coroutines.Free(worker);
  Coroutines.Free(copy);
  Out.String("a second Free, through a copy: nothing"); Out.Ln;
  Coroutines.Transfer(main, copy);
  Out.String("not reached"); Out.Ln
END CoroutineFree.
