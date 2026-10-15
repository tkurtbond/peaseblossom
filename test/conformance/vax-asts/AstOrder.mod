MODULE AstOrder;

  (* Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
     proposals 1, 4, 5 and 8): when ASTs are delivered. Each AST routine
     notes its parameter in log, and the main line prints what log holds
     at each point: an AST queued by $DCLAST is delivered before the next
     statement; one queued while Disable holds is delivered by Restore;
     a timer's routine gets the parameter After gave it; a cancelled timer
     calls nothing; a mailbox read queued by the main line is completed by
     a $QIOW write in a timer's AST, and its completion AST waits for that
     AST to return. *)

  IMPORT SYSTEM, Out, AsynchronousTraps, EventFlags, Timers, Conditions,
    STARLET, IODEF, VmsArguments;

  VAR
    log: ARRAY 32 OF SYSTEM.CARD32;
    logged: INTEGER;
    flag: SYSTEM.CARD32;
    inProgress: BOOLEAN;
    mailbox: SYSTEM.CARD16;
    readStatus, writeStatus: VmsArguments.IOStatusBlock;
    received: ARRAY 64 OF CHAR;
    writeResult: SYSTEM.INT32;

  (* an AST routine: notes parameter *)
  PROCEDURE Note(parameter: SYSTEM.CARD32);
  BEGIN
    IF logged < LEN(log) THEN log[logged] := parameter; INC(logged) END
  END Note;

  (* an AST routine: notes parameter, whether it is at AST level, and
     sets flag *)
  PROCEDURE Tick(parameter: SYSTEM.CARD32);
    VAR status: SYSTEM.INT32;
  BEGIN
    Note(parameter);
    inProgress := AsynchronousTraps.InProgress();
    status := EventFlags.Set(flag)
  END Tick;

  (* an AST routine, a timer's: writes to the mailbox by $QIOW, which
     completes the main line's read; the read's AST waits until this
     returns *)
  PROCEDURE Writer(parameter: SYSTEM.CARD32);
    VAR message: ARRAY 16 OF CHAR;
  BEGIN
    Note(parameter);
    message := "from an AST";
    writeResult := STARLET.SYS$QIOW(0, mailbox, IODEF.IO$_WRITEVBLK + IODEF.IO$M_NOW,
      writeStatus, NIL, 0, message, 11, 0, 0, 0, 0)
  END Writer;

  (* an AST routine, the mailbox read's completion *)
  PROCEDURE ReadDone(parameter: SYSTEM.CARD32);
    VAR status: SYSTEM.INT32;
  BEGIN
    Note(parameter);
    status := EventFlags.Set(flag)
  END ReadDone;

  PROCEDURE Show(what: ARRAY OF CHAR);
    VAR i: INTEGER; wasEnabled: BOOLEAN; copy: ARRAY 32 OF SYSTEM.CARD32; count: INTEGER;
  BEGIN
    wasEnabled := AsynchronousTraps.Disable();
    count := logged; copy := log; logged := 0;
    AsynchronousTraps.Restore(wasEnabled);
    Out.String(what); Out.String(":");
    FOR i := 0 TO count - 1 DO Out.Char(" "); Out.Card(copy[i], 0) END;
    Out.Ln
  END Show;

  PROCEDURE Check(what: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 100 OF CHAR;
  BEGIN
    IF ~Conditions.Succeeded(status) THEN
      Conditions.Message(status, text);
      Out.String(what); Out.String(": "); Out.String(text); Out.Ln
    END
  END Check;

  PROCEDURE Run;
    VAR wasEnabled, again: BOOLEAN; n: INTEGER;
  BEGIN
    Out.String("main line at AST level: ");
    IF AsynchronousTraps.InProgress() THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;

    Check("Declare", AsynchronousTraps.Declare(Note, 1));
    Show("after Declare(1)");

    wasEnabled := AsynchronousTraps.Disable();
    Check("Declare", AsynchronousTraps.Declare(Note, 2));
    n := logged;
    again := AsynchronousTraps.Disable();
    AsynchronousTraps.Restore(again);
    Out.String("Disable: was enabled "); IF wasEnabled THEN Out.String("yes") ELSE Out.String("no") END;
    Out.String(", again "); IF again THEN Out.String("yes") ELSE Out.String("no") END;
    Out.String(", noted while disabled "); Out.Int(n, 0); Out.Ln;
    AsynchronousTraps.Restore(wasEnabled);
    Show("after Restore");

    Check("Get", EventFlags.Get(flag));
    Check("Clear", EventFlags.Clear(flag));
    Check("After", Timers.After(50, Tick, 7));
    Check("Wait", EventFlags.Wait(flag));
    Show("after a timer of 50 ms");
    Out.String("the timer's routine at AST level: ");
    IF inProgress THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
    Out.String("flag set: "); IF EventFlags.IsSet(flag) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
    Check("Clear", EventFlags.Clear(flag));
    Out.String("flag set after Clear: "); IF EventFlags.IsSet(flag) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;

    wasEnabled := AsynchronousTraps.Disable();
    Check("After", Timers.After(20, Note, 8));
    Check("Sleep", Timers.Sleep(300));
    n := logged;
    AsynchronousTraps.Restore(wasEnabled);
    Out.String("expired while disabled, noted before Restore: "); Out.Int(n, 0); Out.Ln;
    Show("after Restore");

    Check("After", Timers.After(100, Note, 9));
    Check("Cancel", Timers.Cancel(9));
    Check("Sleep", Timers.Sleep(300));
    Show("cancelled timer, after 300 ms");

    Check("CREMBX", STARLET.SYS$CREMBX(0, mailbox, 64, 128, 0, 0, NIL, 0));
    Check("QIO", STARLET.SYS$QIO(0, mailbox, IODEF.IO$_READVBLK, readStatus, ReadDone, 10,
      received, LEN(received) - 1, 0, 0, 0, 0));
    Check("After", Timers.After(20, Writer, 11));
    Check("Wait", EventFlags.Wait(flag));
    Show("mailbox");
    Check("write", writeResult);
    Check("write status", SYSTEM.VAL(SYSTEM.INT32, LONG(writeStatus.status)));
    Check("read status", SYSTEM.VAL(SYSTEM.INT32, LONG(readStatus.status)));
    received[readStatus.count] := 0X;
    Out.String("read "); Out.Card(readStatus.count, 0); Out.String(" characters: ");
    Out.String(received); Out.Ln;
    Check("Free", EventFlags.Free(flag))
  END Run;

BEGIN
  Run
END AstOrder.
