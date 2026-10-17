MODULE Mailbox;
  IMPORT SYSTEM, Out, EventFlags, STARLET, IODEF, VmsArguments;

  VAR
    channel: SYSTEM.CARD16;
    readStatus: VmsArguments.IOStatusBlock;
    received: ARRAY 64 OF CHAR;
    done: SYSTEM.CARD32; (* the event flag ReadDone sets *)

  (* an AST routine, the read's completion *)
  PROCEDURE ReadDone(parameter: SYSTEM.CARD32);
    VAR status: SYSTEM.INT32;
  BEGIN
    received[readStatus.count] := 0X;
    status := EventFlags.Set(done)
  END ReadDone;

  PROCEDURE Run;
    VAR status: SYSTEM.INT32; writeStatus: VmsArguments.IOStatusBlock;
      message: ARRAY 32 OF CHAR;
  BEGIN
    status := EventFlags.Get(done);
    status := EventFlags.Clear(done);
    status := STARLET.SYS$CREMBX(0, channel, 64, 128, 0, 0, NIL, 0);
    status := STARLET.SYS$QIO(0, channel, IODEF.IO$_READVBLK, readStatus,
      ReadDone, 0, received, LEN(received) - 1, 0, 0, 0, 0);
    Out.String("a read is queued"); Out.Ln;
    message := "sent by mailbox";
    status := STARLET.SYS$QIOW(0, channel, IODEF.IO$_WRITEVBLK + IODEF.IO$M_NOW,
      writeStatus, NIL, 0, message, 15, 0, 0, 0, 0);
    Out.String("wrote "); Out.Card(writeStatus.count, 0); Out.String(" characters"); Out.Ln;
    status := EventFlags.Wait(done);
    Out.String("read "); Out.Card(readStatus.count, 0); Out.String(" characters: ");
    Out.String(received); Out.Ln;
    status := STARLET.SYS$DASSGN(channel);
    status := EventFlags.Free(done)
  END Run;

BEGIN
  Run
END Mailbox.
