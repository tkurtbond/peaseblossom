MODULE ServiceUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 12): the
     synchronous system services of the supported tier not called
     elsewhere, through the generated STARLET: $GETSYIW and $GETDVIW by
     item lists; a mailbox by $CREMBX, written and read by $QIOW, and
     $DASSGN; $NUMTIM; $FAO, by a declaration of its own with two
     parameters, and $FAOL; locks by $ENQW and $DEQ, with a lock value
     block; $WAKE and $HIBER; and $SETPRN. It prints only what does not
     change from run to run on the guest. *)
  IMPORT SYSTEM, Out, VmsArguments, Timers, EventFlags,
    STARLET, LIB_ROUTINES, SSDEF, SYIDEF, DVIDEF, DCDEF, IODEF, LCKDEF, JPIDEF, CLIDEF;

  CONST
    resource = "POC_SSTEST";

  VAR
    status: SYSTEM.INT32;
    iosb: VmsArguments.IOStatusBlock;
    items: ARRAY 4 OF VmsArguments.ItemListEntry3;
    version: ARRAY 9 OF CHAR;
    hardware: ARRAY 64 OF CHAR;
    cpu, deviceClass, bufferSize, unknown: SYSTEM.CARD32;
    deviceName: ARRAY 65 OF CHAR;
    length1, length2, length3: SYSTEM.CARD16;
    channel: SYSTEM.CARD16;
    line: ARRAY 64 OF CHAR;
    time, zero, delta, before, after: HUGEINT;
    words: ARRAY 7 OF SYSTEM.CARD16;
    text: ARRAY 128 OF CHAR;
    textLength: SYSTEM.CARD16;
    parameters: ARRAY 2 OF SYSTEM.CARD32;
    descriptor: VmsArguments.StringDescriptor;
    name: ARRAY 16 OF CHAR;
    a, b, c: VmsArguments.LockStatusBlock;
    original, current: ARRAY 16 OF CHAR;
    originalLength, currentLength: SYSTEM.CARD16;
    flagNumber: SYSTEM.CARD32;
    flag: SYSTEM.CARD8;
    tries: INTEGER;
    i: INTEGER;

  (* $FAO with two parameters: VMS takes as many as the control string uses *)
  PROCEDURE ["VMS", "SYS$FAO"] Format2(control-: ARRAY OF CHAR; VAR length: SYSTEM.CARD16;
                                       VAR buffer: ARRAY OF CHAR; p1, p2: SYSTEM.CARD32): SYSTEM.INT32;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = SSDEF.SS$_SYNCH THEN Out.String("SS$_SYNCH")
    ELSIF status = SSDEF.SS$_NOTQUEUED THEN Out.String("SS$_NOTQUEUED")
    ELSIF status = SSDEF.SS$_VALNOTVALID THEN Out.String("SS$_VALNOTVALID")
    ELSIF status = SSDEF.SS$_IVLOCKID THEN Out.String("SS$_IVLOCKID")
    ELSIF status = SSDEF.SS$_BADPARAM THEN Out.String("SS$_BADPARAM")
    ELSIF status = SSDEF.SS$_ENDOFFILE THEN Out.String("SS$_ENDOFFILE")
    ELSIF status = SSDEF.SS$_IVCHAN THEN Out.String("SS$_IVCHAN")
    ELSIF status = SSDEF.SS$_NONEXPR THEN Out.String("SS$_NONEXPR")
    ELSIF status = SSDEF.SS$_IVLOGNAM THEN Out.String("SS$_IVLOGNAM")
    ELSIF status = SSDEF.SS$_DUPLNAM THEN Out.String("SS$_DUPLNAM")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* a status word of a status block, as a condition value *)
  PROCEDURE Word(w: SYSTEM.CARD16): SYSTEM.INT32;
  BEGIN
    RETURN SYSTEM.VAL(SYSTEM.INT32, w)
  END Word;

  (* s ended at length, its trailing blanks removed *)
  PROCEDURE Cut(VAR s: ARRAY OF CHAR; length: SYSTEM.CARD16);
    VAR n: LONGINT;
  BEGIN
    n := SYSTEM.VAL(SYSTEM.INT32, length);
    IF n > LEN(s) - 1 THEN n := LEN(s) - 1 END;
    WHILE (n > 0) & (s[n - 1] = " ") DO DEC(n) END;
    s[n] := 0X
  END Cut;

  PROCEDURE ShowText(what: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; length: SYSTEM.CARD16);
  BEGIN
    Cut(s, length);
    Out.String("  "); Out.String(what); Out.String(" |"); Out.String(s); Out.String("|"); Out.Ln
  END ShowText;

  PROCEDURE SetValue(VAR lsb: VmsArguments.LockStatusBlock; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 15 DO lsb.value[i] := 0X END;
    i := 0;
    WHILE (i < 16) & (s[i] # 0X) DO lsb.value[i] := s[i]; INC(i) END
  END SetValue;

  PROCEDURE ShowValue(VAR lsb: VmsArguments.LockStatusBlock);
    VAR i: INTEGER; s: ARRAY 17 OF CHAR;
  BEGIN
    FOR i := 0 TO 15 DO s[i] := SYSTEM.VAL(CHAR, lsb.value[i]) END;
    s[16] := 0X;
    Out.String("  value |"); Out.String(s); Out.String("|"); Out.Ln
  END ShowValue;

  PROCEDURE Lock(what: ARRAY OF CHAR; VAR lsb: VmsArguments.LockStatusBlock; mode, flags: SYSTEM.CARD32);
  BEGIN
    Show(what, STARLET.SYS$ENQW(0, mode, lsb, flags, resource, 0, NIL, 0, NIL, 0, 0, 0, 0));
    Show("  in the lock status block", Word(lsb.status))
  END Lock;

BEGIN
  Out.String("$GETSYIW"); Out.Ln;
  VmsArguments.SetItem(items, 0, SYIDEF.SYI$_VERSION, version, length1);
  VmsArguments.SetItem(items, 1, SYIDEF.SYI$_HW_NAME, hardware, length2);
  VmsArguments.SetItem(items, 2, SYIDEF.SYI$_CPU, cpu, length3);
  VmsArguments.EndList(items, 3);
  Show("version, hardware, CPU", STARLET.SYS$GETSYIW(0, NIL, NIL, items, iosb, NIL, 0));
  Show("  I/O status", Word(iosb.status));
  ShowText("SYI$_VERSION", version, length1);
  ShowText("SYI$_HW_NAME", hardware, length2);
  Out.String("  SYI$_CPU "); Out.Card(cpu, 0); Out.String(", length "); Out.Card(length3, 0); Out.Ln;
  VmsArguments.SetItem(items, 0, 9999, unknown, length1);
  VmsArguments.EndList(items, 1);
  iosb.status := 0;
  Show("item 9999", STARLET.SYS$GETSYIW(0, NIL, NIL, items, iosb, NIL, 0));

  Out.String("$GETDVIW"); Out.Ln;
  deviceClass := 0;
  VmsArguments.SetItem(items, 0, DVIDEF.DVI$_DEVCLASS, deviceClass, length1);
  VmsArguments.SetItem(items, 1, DVIDEF.DVI$_DEVNAM, deviceName, length2);
  VmsArguments.EndList(items, 2);
  Show("SYS$DISK", STARLET.SYS$GETDVIW(0, 0, "SYS$DISK", items, iosb, NIL, 0, NIL));
  Show("  I/O status", Word(iosb.status));
  Out.String("  DVI$_DEVCLASS is DC$_DISK: ");
  IF deviceClass = DCDEF.DC$_DISK THEN Out.String("yes") ELSE Out.Card(deviceClass, 0) END; Out.Ln;
  ShowText("DVI$_DEVNAM", deviceName, length2);

  Out.String("a mailbox"); Out.Ln;
  Show("$CREMBX", STARLET.SYS$CREMBX(0, channel, 64, 256, 0, 0, NIL, 0));
  deviceClass := 0; bufferSize := 0;
  VmsArguments.SetItem(items, 0, DVIDEF.DVI$_DEVCLASS, deviceClass, length1);
  VmsArguments.SetItem(items, 1, DVIDEF.DVI$_DEVBUFSIZ, bufferSize, length2);
  VmsArguments.EndList(items, 2);
  Show("$GETDVIW by channel", STARLET.SYS$GETDVIW(0, channel, NIL, items, iosb, NIL, 0, NIL));
  Out.String("  DVI$_DEVCLASS is DC$_MAILBOX: ");
  IF deviceClass = DCDEF.DC$_MAILBOX THEN Out.String("yes") ELSE Out.Card(deviceClass, 0) END;
  Out.String(", DVI$_DEVBUFSIZ "); Out.Card(bufferSize, 0); Out.Ln;
  line := "a line through the mailbox";
  Show("$QIOW write", STARLET.SYS$QIOW(0, channel, IODEF.IO$_WRITEVBLK + IODEF.IO$M_NOW, iosb, NIL, 0,
    line, 26, 0, 0, 0, 0));
  Show("  I/O status", Word(iosb.status));
  line := "";
  Show("$QIOW read", STARLET.SYS$QIOW(0, channel, IODEF.IO$_READVBLK, iosb, NIL, 0,
    line, LEN(line) - 1, 0, 0, 0, 0));
  Show("  I/O status", Word(iosb.status));
  ShowText("read", line, iosb.count);
  Show("$QIOW read, empty, IO$M_NOW", STARLET.SYS$QIOW(0, channel, IODEF.IO$_READVBLK + IODEF.IO$M_NOW, iosb,
    NIL, 0, line, LEN(line) - 1, 0, 0, 0, 0));
  Show("  I/O status", Word(iosb.status));
  Show("$DASSGN", STARLET.SYS$DASSGN(channel));
  Show("$DASSGN again", STARLET.SYS$DASSGN(channel));

  Out.String("$NUMTIM"); Out.Ln;
  status := STARLET.SYS$BINTIM("16-OCT-2026 12:34:56.78", time);
  Show("16-OCT-2026 12:34:56.78", STARLET.SYS$NUMTIM(words, time));
  Out.String(" ");
  FOR i := 0 TO 6 DO Out.Char(" "); Out.Card(words[i], 0) END; Out.Ln;
  zero := 0;
  Show("0", STARLET.SYS$NUMTIM(words, zero));
  Out.String(" ");
  FOR i := 0 TO 6 DO Out.Char(" "); Out.Card(words[i], 0) END; Out.Ln;
  status := STARLET.SYS$BINTIM("3 04:00:00.00", delta);
  Show("a delta of 3 04:00:00.00", STARLET.SYS$NUMTIM(words, delta));
  Out.String(" ");
  FOR i := 0 TO 6 DO Out.Char(" "); Out.Card(words[i], 0) END; Out.Ln;
  Show("now", STARLET.SYS$NUMTIM(words, NIL));

  Out.String("$FAO and $FAOL"); Out.Ln;
  Show("!UL and !XL", Format2("!UL and !XL", textLength, text, 42, 255));
  ShowText("", text, textLength);
  name := "a string";
  VmsArguments.Describe(descriptor, name);
  Show("!AS, !SL", Format2("!AS, !SL", textLength, text,
    SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(descriptor)), SYSTEM.VAL(SYSTEM.CARD32, -42)));
  ShowText("", text, textLength);
  Show("!%D, !UL", Format2("!%D, !UL", textLength, text, SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(time)), 7));
  ShowText("", text, textLength);
  parameters[0] := 42; parameters[1] := 255;
  Show("$FAOL !UL and !XL", STARLET.SYS$FAOL("!UL and !XL", textLength, text, parameters));
  ShowText("", text, textLength);

  Out.String("$ENQW and $DEQ on "); Out.String(resource); Out.Ln;
  Lock("A, EX, VALBLK", a, LCKDEF.LCK$K_EXMODE, LCKDEF.LCK$M_VALBLK);
  Out.String("  A's lock id is not 0: "); IF a.lockId # 0 THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  ShowValue(a);
  Show("B, EX, NOQUEUE", STARLET.SYS$ENQW(0, LCKDEF.LCK$K_EXMODE, b, LCKDEF.LCK$M_NOQUEUE, resource,
    0, NIL, 0, NIL, 0, 0, 0, 0));
  Show("B, CR, NOQUEUE", STARLET.SYS$ENQW(0, LCKDEF.LCK$K_CRMODE, b, LCKDEF.LCK$M_NOQUEUE, resource,
    0, NIL, 0, NIL, 0, 0, 0, 0));
  Lock("B, NL", b, LCKDEF.LCK$K_NLMODE, 0);
  SetValue(a, "from lock A");
  Lock("A converted to NL, VALBLK", a, LCKDEF.LCK$K_NLMODE, LCKDEF.LCK$M_CONVERT + LCKDEF.LCK$M_VALBLK);
  Lock("B converted to PR, VALBLK", b, LCKDEF.LCK$K_PRMODE, LCKDEF.LCK$M_CONVERT + LCKDEF.LCK$M_VALBLK);
  ShowValue(b);
  Lock("C, NL, SYNCSTS", c, LCKDEF.LCK$K_NLMODE, LCKDEF.LCK$M_SYNCSTS);
  Show("$DEQ A", STARLET.SYS$DEQ(a.lockId, NIL, 0, 0));
  Show("$DEQ B", STARLET.SYS$DEQ(b.lockId, NIL, 0, 0));
  Show("$DEQ C", STARLET.SYS$DEQ(c.lockId, NIL, 0, 0));
  Show("$DEQ A again", STARLET.SYS$DEQ(a.lockId, NIL, 0, 0));

  Out.String("$WAKE and $HIBER"); Out.Ln;
  Show("$WAKE", STARLET.SYS$WAKE(NIL, NIL));
  Show("$HIBER", STARLET.SYS$HIBER());
  Show("$WAKE", STARLET.SYS$WAKE(NIL, NIL));
  Show("$WAKE", STARLET.SYS$WAKE(NIL, NIL));
  Show("$HIBER", STARLET.SYS$HIBER());
  status := STARLET.SYS$GETTIM(before);
  Show("Timers.Sleep(2000)", Timers.Sleep(2000));
  status := STARLET.SYS$GETTIM(after);
  Out.String("  at least 1.5 seconds: ");
  IF after - before >= 15000000 THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Show("$WAKE POC_NO_SUCH", STARLET.SYS$WAKE(NIL, "POC_NO_SUCH"));

  Out.String("$SETPRN"); Out.Ln;
  VmsArguments.SetItem(items, 0, JPIDEF.JPI$_PRCNAM, original, originalLength);
  VmsArguments.EndList(items, 1);
  Show("$GETJPIW", STARLET.SYS$GETJPIW(0, NIL, NIL, items, iosb, NIL, 0));
  Cut(original, originalLength);
  Show("POC_SSTEST", STARLET.SYS$SETPRN("POC_SSTEST"));
  VmsArguments.SetItem(items, 0, JPIDEF.JPI$_PRCNAM, current, currentLength);
  status := STARLET.SYS$GETJPIW(0, NIL, NIL, items, iosb, NIL, 0);
  ShowText("JPI$_PRCNAM", current, currentLength);
  Show("POC_SSTEST_LONG_", STARLET.SYS$SETPRN("POC_SSTEST_LONG_"));
  status := EventFlags.Get(flagNumber); status := EventFlags.Clear(flagNumber);
  flag := SHORT(SHORT(flagNumber));
  Show("a subprocess POC_SSDUP", LIB_ROUTINES.LIB$SPAWN("WAIT 00:00:03", NIL, NIL, CLIDEF.CLI$M_NOWAIT,
    "POC_SSDUP", NIL, 0, flag, NIL, 0, NIL, NIL, NIL));
  Show("POC_SSDUP", STARLET.SYS$SETPRN("POC_SSDUP"));
  tries := 0;
  WHILE ~EventFlags.IsSet(flagNumber) & (tries < 300) DO status := Timers.Sleep(100); INC(tries) END;
  status := EventFlags.Free(flagNumber);
  Show("the first name again", STARLET.SYS$SETPRN(original));
  status := STARLET.SYS$GETJPIW(0, NIL, NIL, items, iosb, NIL, 0);
  Cut(current, currentLength);
  Out.String("  restored: "); IF current = original THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln
END ServiceUse.
