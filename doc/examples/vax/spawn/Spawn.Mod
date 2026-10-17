MODULE Spawn;
  IMPORT SYSTEM, Out, Platform, Subprocesses, Timers, LIB_ROUTINES, JPIDEF;

  VAR
    status, completion: SYSTEM.INT32;
    result: INTEGER;
    job: Subprocesses.Subprocess;

  (* waits, at most 10 seconds, until VMS has deleted every subprocess of
     this process that has ended, so that the next one fits the quota *)
  PROCEDURE AwaitNone;
    VAR count, status: SYSTEM.INT32; tries: INTEGER;
  BEGIN
    tries := 0;
    REPEAT
      count := 0;
      status := LIB_ROUTINES.LIB$GETJPI(JPIDEF.JPI$_PRCCNT, NIL, NIL, count, NIL, NIL);
      IF count # 0 THEN status := Timers.Sleep(100); INC(tries) END
    UNTIL (count = 0) OR (tries = 100)
  END AwaitNone;

  PROCEDURE Report(what: ARRAY OF CHAR; status, completion: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF ~ODD(status) THEN Out.String("not started, %X"); Out.Hex(status, 8)
    ELSIF ODD(completion) THEN Out.String("succeeded")
    ELSE Out.String("failed, %X"); Out.Hex(completion, 8)
    END;
    Out.Ln
  END Report;

  PROCEDURE YesNo(what: ARRAY OF CHAR; answer: BOOLEAN);
  BEGIN
    Out.String(what); Out.String(": ");
    IF answer THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END YesNo;

BEGIN
  status := Subprocesses.Run('WRITE SYS$OUTPUT "from a subprocess"', "", "", {}, completion);
  Report("WRITE", status, completion);

  AwaitNone;
  status := Subprocesses.Run("EXIT 44", "", "", {}, completion);
  Report("EXIT 44", status, completion);

  AwaitNone;
  result := Platform.System("EXIT 44");
  Out.String("Platform.System: "); Out.Int(result, 0); Out.Ln;

  AwaitNone;
  status := Subprocesses.Start("WAIT 00:00:01", "", "", {}, job);
  YesNo("ended at once", Subprocesses.Done(job));
  completion := Subprocesses.Wait(job);
  YesNo("ended after Wait", Subprocesses.Done(job));
  Report("WAIT 00:00:01", status, completion);

  AwaitNone;
  status := Subprocesses.Start("WAIT 00:01:00", "", "", {}, job);
  status := Subprocesses.Stop(job);
  Report("WAIT 00:01:00, stopped", status, Subprocesses.Wait(job))
END Spawn.
