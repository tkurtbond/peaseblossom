MODULE InfoUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10):
     LIB$GETJPI, LIB$GETSYI, LIB$GETDVI and LIB$GETQUI through LIB_ROUTINES,
     one item at a time. Only what does not change from run to run is
     printed, a string between bars to show its padding; the PID's value
     and its string are checked against each other. LIB$GETQUI asks about
     the guest's one queue, SYS$BATCH, by name, by a wildcard walk, and by
     a wildcard frozen on it. Then the errors: an item code that is none,
     a string-only item with no string, a string too short, a queue that
     does not exist. *)
  IMPORT SYSTEM, Out, LIB_ROUTINES, JPIDEF, SYIDEF, DVIDEF, DCDEF, QUIDEF, JBCMSGDEF, LIBDEF, SSDEF;

  VAR
    text: ARRAY 64 OF CHAR;
    short: ARRAY 2 OF CHAR;
    length: SYSTEM.CARD16;
    value, pid: SYSTEM.INT32;
    status: SYSTEM.INT32;
    hex: ARRAY 9 OF CHAR;
    i: INTEGER;
    digit: SYSTEM.INT32;
    queueLength: SYSTEM.INT16;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = SSDEF.SS$_BADPARAM THEN Out.String("SS$_BADPARAM")
    ELSIF status = LIBDEF.LIB$_INVARG THEN Out.String("LIB$_INVARG")
    ELSIF status = LIBDEF.LIB$_STRTRU THEN Out.String("LIB$_STRTRU")
    ELSIF status = JBCMSGDEF.JBC$_NOSUCHQUE THEN Out.String("JBC$_NOSUCHQUE")
    ELSIF status = JBCMSGDEF.JBC$_NOMOREQUE THEN Out.String("JBC$_NOMOREQUE")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* text, length characters of it, between bars *)
  PROCEDURE PrintText;
    VAR n: LONGINT;
  BEGIN
    n := SYSTEM.VAL(SYSTEM.INT32, length);
    IF n > LEN(text) - 1 THEN n := LEN(text) - 1 END;
    text[n] := 0X;
    Out.String("  |"); Out.String(text); Out.String("|, length "); Out.Int(n, 0); Out.Ln
  END PrintText;

  PROCEDURE Process(what: ARRAY OF CHAR; item: SYSTEM.INT32);
  BEGIN
    length := 0;
    Show(what, LIB_ROUTINES.LIB$GETJPI(item, NIL, NIL, NIL, text, length)); PrintText
  END Process;

  PROCEDURE System(what: ARRAY OF CHAR; item: SYSTEM.INT32);
  BEGIN
    length := 0;
    Show(what, LIB_ROUTINES.LIB$GETSYI(item, NIL, text, length, NIL, NIL)); PrintText
  END System;

  (* item of the queue name finds by function, with flags, NIL if 0; its
     value and its string *)
  PROCEDURE Queue(what: ARRAY OF CHAR; function, item: SYSTEM.INT32; name: ARRAY OF CHAR; flags: SYSTEM.CARD32);
    VAR status: SYSTEM.INT32;
  BEGIN
    value := 0; queueLength := 0; text[0] := 0X;
    IF flags = 0 THEN
      status := LIB_ROUTINES.LIB$GETQUI(function, item, NIL, name, NIL, value, text, queueLength)
    ELSE
      status := LIB_ROUTINES.LIB$GETQUI(function, item, NIL, name, flags, value, text, queueLength)
    END;
    Show(what, status);
    length := SYSTEM.VAL(SYSTEM.CARD16, queueLength);
    Out.String("  value "); Out.Int(value, 0); PrintText
  END Queue;

BEGIN
  Out.String("LIB$GETJPI"); Out.Ln;
  Process("JPI$_USERNAME", JPIDEF.JPI$_USERNAME);
  Process("JPI$_MODE", JPIDEF.JPI$_MODE);
  length := 0; pid := 0;
  Show("JPI$_PID", LIB_ROUTINES.LIB$GETJPI(JPIDEF.JPI$_PID, NIL, NIL, pid, text, length));
  text[SYSTEM.VAL(SYSTEM.INT32, length)] := 0X;
  FOR i := 7 TO 0 BY -1 DO
    digit := SYSTEM.VAL(SYSTEM.INT32, SYSTEM.VAL(SET, SYSTEM.LSH(pid, -4 * (7 - i))) * {0..3});
    IF digit < 10 THEN hex[i] := CHR(ORD("0") + digit) ELSE hex[i] := CHR(ORD("A") + digit - 10) END
  END;
  hex[8] := 0X;
  Out.String("  string of length "); Out.Int(SYSTEM.VAL(SYSTEM.INT32, length), 0);
  Out.String(", the value in hex: ");
  IF text = hex THEN Out.String("the same") ELSE Out.String("different: "); Out.String(text); Out.String(" "); Out.String(hex) END;
  Out.Ln;

  Out.String("LIB$GETSYI"); Out.Ln;
  System("SYI$_VERSION", SYIDEF.SYI$_VERSION);
  System("SYI$_NODENAME", SYIDEF.SYI$_NODENAME);

  Out.String("LIB$GETDVI"); Out.Ln;
  value := 0;
  Show("DVI$_DEVCLASS of SYS$LOGIN", LIB_ROUTINES.LIB$GETDVI(DVIDEF.DVI$_DEVCLASS, NIL, "SYS$LOGIN", value, NIL, NIL));
  Out.String("  a disk: ");
  IF value = DCDEF.DC$_DISK THEN Out.String("yes") ELSE Out.String("no, "); Out.Int(value, 0) END; Out.Ln;
  length := 0;
  Show("DVI$_DEVCLASS's string", LIB_ROUTINES.LIB$GETDVI(DVIDEF.DVI$_DEVCLASS, NIL, "SYS$LOGIN", NIL, text, length));
  PrintText;

  Out.String("LIB$GETQUI"); Out.Ln;
  Queue("SYS$BATCH's QUI$_QUEUE_NAME", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_QUEUE_NAME, "SYS$BATCH", 0);
  Queue("SYS$BATCH's QUI$_JOB_LIMIT", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_JOB_LIMIT, "SYS$BATCH", 0);
  Queue("SYS$BATCH's QUI$_QUEUE_FLAGS", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_QUEUE_FLAGS, "SYS$BATCH", 0);
  Out.String("  a batch queue: ");
  IF ODD(value) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Queue("QUI$_TRANSLATE_QUEUE of sys$batch", QUIDEF.QUI$_TRANSLATE_QUEUE, QUIDEF.QUI$_QUEUE_NAME, "sys$batch", 0);
  Out.String("a wildcard walk, three calls"); Out.Ln;
  FOR i := 1 TO 3 DO
    Queue("* QUI$_QUEUE_NAME", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_QUEUE_NAME, "*", 0)
  END;
  Out.String("a wildcard frozen on its queue"); Out.Ln;
  Queue("* QUI$_QUEUE_NAME, frozen", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_QUEUE_NAME, "*",
    QUIDEF.QUI$M_SEARCH_FREEZE_CONTEXT);
  Queue("* QUI$_JOB_LIMIT, frozen", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_JOB_LIMIT, "*",
    QUIDEF.QUI$M_SEARCH_FREEZE_CONTEXT);
  Show("QUI$_CANCEL_OPERATION", LIB_ROUTINES.LIB$GETQUI(QUIDEF.QUI$_CANCEL_OPERATION, NIL, NIL, NIL, NIL, NIL, NIL, NIL));
  Queue("* QUI$_QUEUE_NAME after the cancel", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_QUEUE_NAME, "*", 0);
  Show("QUI$_CANCEL_OPERATION", LIB_ROUTINES.LIB$GETQUI(QUIDEF.QUI$_CANCEL_OPERATION, NIL, NIL, NIL, NIL, NIL, NIL, NIL));

  Out.String("errors"); Out.Ln;
  Show("item code 12345", LIB_ROUTINES.LIB$GETJPI(12345, NIL, NIL, value, NIL, NIL));
  Show("JPI$_USERNAME with no string", LIB_ROUTINES.LIB$GETJPI(JPIDEF.JPI$_USERNAME, NIL, NIL, value, NIL, NIL));
  length := 0;
  Show("JPI$_USERNAME into 2 characters", LIB_ROUTINES.LIB$GETJPI(JPIDEF.JPI$_USERNAME, NIL, NIL, NIL, short, length));
  Out.String("  length "); Out.Int(SYSTEM.VAL(SYSTEM.INT32, length), 0); Out.String(", "); Out.Char(short[0]); Out.Char(short[1]); Out.Ln;
  Queue("NO_SUCH_QUEUE's QUI$_QUEUE_NAME", QUIDEF.QUI$_DISPLAY_QUEUE, QUIDEF.QUI$_QUEUE_NAME, "NO_SUCH_QUEUE", 0)
END InfoUse.
