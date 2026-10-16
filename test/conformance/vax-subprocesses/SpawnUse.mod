MODULE SpawnUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 11):
     VMSLIB's Subprocesses, Run and Start, Wait and Stop; LIB$SPAWN itself
     with a completion AST and with a process name twice and one too long; then a chain,
     LIB$PUT_COMMON and LIB$RUN_PROGRAM of ChainedUse, which ends by
     LIB$DO_COMMAND. What it prints does not change from run to run: no
     PID and no process name VMS made. *)
  IMPORT SYSTEM, Out, Files, Subprocesses, Symbols, LogicalNames, Timers, EventFlags,
    LIB_ROUTINES, CLIDEF, SSDEF, LIBDEF, JPIDEF;

  VAR
    status, completion, astStatus, firstStatus: SYSTEM.INT32;
    first, second, stopped: Subprocesses.Subprocess;
    astParameter: SYSTEM.CARD32;
    astCalled: BOOLEAN;
    flags, id, flagNumber: SYSTEM.CARD32;
    flag: SYSTEM.CARD8;
    tries: INTEGER;
    length: SYSTEM.CARD16;
    f: Files.File;
    r: Files.Rider;

  (* until the process has no subprocess, at most 10 seconds: one that has
     ended counts against its subprocess quota, PRCLM, 2 on the guest,
     until VMS has deleted it, so a spawn soon after can fail with
     SS$_EXQUOTA (make test-vax-asts found it before the name test, and a
     gate before Start second). So it runs before each group that starts
     one. Prints only if one is left. *)
  PROCEDURE AwaitNoSubprocess;
    VAR count, status: SYSTEM.INT32; tries: INTEGER;
  BEGIN
    tries := 0;
    REPEAT
      count := 0;
      status := LIB_ROUTINES.LIB$GETJPI(JPIDEF.JPI$_PRCCNT, NIL, NIL, count, NIL, NIL);
      IF count # 0 THEN status := Timers.Sleep(100); INC(tries) END
    UNTIL (count = 0) OR (tries = 100);
    IF count # 0 THEN Out.String("  subprocesses left: "); Out.Int(count, 0); Out.Ln END
  END AwaitNoSubprocess;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = SSDEF.SS$_DUPLNAM THEN Out.String("SS$_DUPLNAM")
    ELSIF status = SSDEF.SS$_EXQUOTA THEN Out.String("SS$_EXQUOTA")
    ELSIF status = SSDEF.SS$_IVLOGNAM THEN Out.String("SS$_IVLOGNAM")
    ELSIF status = LIBDEF.LIB$_NOCLI THEN Out.String("LIB$_NOCLI")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  PROCEDURE ShowCompletion(c: SYSTEM.INT32);
  BEGIN
    Out.String("  completion %X"); Out.Hex(c, 8); Out.Ln
  END ShowCompletion;

  PROCEDURE WriteLine(VAR r: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO Files.Write(r, s[i]); INC(i) END;
    Files.Write(r, 0AX)
  END WriteLine;

  PROCEDURE PrintFile(name: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; c: CHAR; line: ARRAY 80 OF CHAR; n: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN Out.String("  no "); Out.String(name); Out.Ln
    ELSE
      Files.Set(r, f, 0); Files.Read(r, c);
      WHILE ~r.eof DO
        n := 0;
        WHILE ~r.eof & (c # 0AX) DO
          IF n < LEN(line) - 1 THEN line[n] := c; INC(n) END;
          Files.Read(r, c)
        END;
        WHILE (n > 0) & (line[n - 1] = " ") DO DEC(n) END;
        line[n] := 0X;
        Out.String("  | "); Out.String(line); Out.Ln;
        IF ~r.eof THEN Files.Read(r, c) END
      END;
      Files.Close(f)
    END
  END PrintFile;

  (* LIB$SPAWN's completion AST *)
  PROCEDURE Completed(parameter: SYSTEM.CARD32);
  BEGIN
    astParameter := parameter; astCalled := TRUE
  END Completed;

BEGIN
  Out.String("Run"); Out.Ln;
  Show("WRITE, to SPAWN1.OUT", Subprocesses.Run('WRITE SYS$OUTPUT "from a subprocess"', "", "SPAWN1.OUT", {}, completion));
  ShowCompletion(completion); PrintFile("SPAWN1.OUT");
  Show("EXIT 44", Subprocesses.Run("EXIT 44", "", "", {}, completion));
  ShowCompletion(completion);
  Show("WRITE, to the caller's output", Subprocesses.Run('WRITE SYS$OUTPUT "to the output of the caller"', "", "", {}, completion));
  ShowCompletion(completion);

  status := Symbols.Set("POC_SPAWN_SYMBOL", "a symbol", Symbols.Local);
  status := LogicalNames.Define(LogicalNames.Process, "POC_SPAWN_NAME", "a logical name", LogicalNames.User);
  Show("inherited", Subprocesses.Run('WRITE SYS$OUTPUT F$TYPE(POC_SPAWN_SYMBOL), "/", F$TRNLNM("POC_SPAWN_NAME")',
    "", "SPAWN2.OUT", {}, completion));
  PrintFile("SPAWN2.OUT");
  Show("not inherited", Subprocesses.Run('WRITE SYS$OUTPUT F$TYPE(POC_SPAWN_SYMBOL), "/", F$TRNLNM("POC_SPAWN_NAME")',
    "", "SPAWN2.OUT", {Subprocesses.noSymbols, Subprocesses.noLogicalNames}, completion));
  PrintFile("SPAWN2.OUT");

  f := Files.New("SPAWN3.COM"); Files.Set(r, f, 0);
  WriteLine(r, '$ WRITE SYS$OUTPUT "from the input file"');
  WriteLine(r, "$ EXIT 3");
  Files.Register(f); Files.Close(f);
  Show("input SPAWN3.COM", Subprocesses.Run("", "SPAWN3.COM", "SPAWN3.OUT", {}, completion));
  ShowCompletion(completion); PrintFile("SPAWN3.OUT");

  Out.String("Start and Wait"); Out.Ln;
  AwaitNoSubprocess;
  Show("Start first", Subprocesses.Start('WRITE SYS$OUTPUT "first"', "", "SPAWN4.OUT", {}, first));
  Show("Start second", Subprocesses.Start('WRITE SYS$OUTPUT "second"', "", "SPAWN5.OUT", {}, second));
  first := NIL; (* still kept by Subprocesses *)
  ShowCompletion(Subprocesses.Wait(second));
  Out.String("  second done: ");
  IF Subprocesses.Done(second) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  PrintFile("SPAWN5.OUT");
  AwaitNoSubprocess;
  Show("Start WAIT 00:01:00", Subprocesses.Start("WAIT 00:01:00", "", "", {}, stopped));
  Show("Stop", Subprocesses.Stop(stopped));
  ShowCompletion(Subprocesses.Wait(stopped));
  PrintFile("SPAWN4.OUT");

  Out.String("LIB$SPAWN with a completion AST"); Out.Ln;
  AwaitNoSubprocess;
  flags := CLIDEF.CLI$M_NOWAIT; astCalled := FALSE; astStatus := 0;
  Show("LIB$SPAWN", LIB_ROUTINES.LIB$SPAWN('WRITE SYS$OUTPUT "for the AST"', NIL, "SPAWN6.OUT", flags,
    NIL, NIL, SYSTEM.ADR(astStatus), NIL, Completed, 7, NIL, NIL, NIL));
  tries := 0;
  WHILE ~astCalled & (tries < 300) DO status := Timers.Sleep(100); INC(tries) END;
  Out.String("  AST called: ");
  IF astCalled THEN Out.String("yes, parameter "); Out.Card(astParameter, 0) ELSE Out.String("no") END; Out.Ln;
  ShowCompletion(astStatus); PrintFile("SPAWN6.OUT");

  (* a process name has at most 15 characters; the third is 17 *)
  Out.String("LIB$SPAWN with a process name, twice, and one too long"); Out.Ln;
  AwaitNoSubprocess;
  status := EventFlags.Get(flagNumber); status := EventFlags.Clear(flagNumber);
  flag := SHORT(SHORT(flagNumber)); id := 0; firstStatus := 0;
  Show("first", LIB_ROUTINES.LIB$SPAWN("WAIT 00:00:02", NIL, NIL, flags, "POC_SPAWN_TEST", id,
    SYSTEM.ADR(firstStatus), flag, NIL, 0, NIL, NIL, NIL));
  Show("second", LIB_ROUTINES.LIB$SPAWN("WAIT 00:00:02", NIL, NIL, flags, "POC_SPAWN_TEST", NIL,
    0, NIL, NIL, 0, NIL, NIL, NIL));
  Show("too long", LIB_ROUTINES.LIB$SPAWN("WAIT 00:00:02", NIL, NIL, flags, "POC_SPAWN_FIXTURE", NIL,
    0, NIL, NIL, 0, NIL, NIL, NIL));
  (* at most 30 seconds, so that a spawn that failed cannot hang the fixture *)
  tries := 0;
  WHILE ~EventFlags.IsSet(flagNumber) & (tries < 300) DO status := Timers.Sleep(100); INC(tries) END;
  status := EventFlags.Free(flagNumber);
  Out.String("  the first ended: ");
  IF tries < 300 THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  ShowCompletion(firstStatus);

  Out.String("the chain"); Out.Ln;
  length := 0;
  Show("LIB$PUT_COMMON", LIB_ROUTINES.LIB$PUT_COMMON("a line through the common area", length));
  Out.String("  length "); Out.Card(length, 0); Out.Ln;
  Out.String("a line with no Ln, before LIB$RUN_PROGRAM");
  Show("LIB$RUN_PROGRAM", LIB_ROUTINES.LIB$RUN_PROGRAM("CHAINEDUSE"))
END SpawnUse.
