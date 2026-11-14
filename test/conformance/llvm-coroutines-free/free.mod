MODULE free;
  (* Free gives a stack back: 2000 coroutines of 4 MiB each, run and
     freed one after another, fit in the 1 GB the fixture's ulimit allows,
     where they could not without Free. Free of a record never given to
     Init and a second Free do nothing; a Transfer to a freed coroutine
     through another copy of its record traps. *)
  IMPORT Coroutines, Out;

  CONST rounds = 2000; size = 4194304;

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
  Out.String("ran "); Out.Int(ran DIV 1023, 0); Out.String(" coroutines of 4 MiB"); Out.Ln;
  Coroutines.Init(Work, size, worker);
  copy := worker;
  Coroutines.Free(worker);
  Coroutines.Free(copy);
  Out.String("a second Free, through a copy: nothing"); Out.Ln;
  Coroutines.Transfer(main, copy);
  Out.String("not reached"); Out.Ln
END free.
