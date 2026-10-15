MODULE VmsDefCalls;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 2): real
     VMS routines called through the declarations tools/sdloberon wrote
     from STARLETSD.TLB (rtl/vax/vms), with their constants - LIB$ and
     STR$ strings by descriptor; LIB$GET_VM's address out; $TRNLNM's and
     $GETJPIW's item lists and I/O status block as ARRAY OF SYSTEM.BYTE
     (part 2, proposal 7); $BINTIM and $ASCTIM, a quadword in, an x-:
     HUGEINT, from a variable and from a constant; $ASSIGN and $QIOW, a
     string constant as P1; and RMS's $OPEN and $CLOSE with a FAB of
     FABDEF's record type, whose fields RMS fills in. SDL's unsigned lengths, channels and
     fields are CARDs (part 3): an address into an unsigned longword by
     SYSTEM.VAL, a CARD printed by Out.Card. An AST routine parameter is
     an AsynchronousTraps.Routine, which NIL omits (Phase 17 step 6,
     doc/developer/vax-macro32-backend.md, section 22.3, proposal 1). Run
     by guest-run.com, which makes VMSDEFCALLS.TXT and defines
     POC_VMSDEF_LNM. *)
  IMPORT SYSTEM, Out, VmsArguments, STARLET, LIB_ROUTINES, STR_ROUTINES,
    SSDEF, LNMDEF, JPIDEF, IODEF, FABDEF, RMSDEF;

  CONST
    fileName = "VMSDEFCALLS.TXT";
    oneMinute = -600000000; (* a delta time, in 100-nanosecond units *)
    localSymbol = 1; (* LIB$K_CLI_LOCAL_SYM *)

  VAR
    status: LONGINT;
    value, upper: ARRAY 64 OF CHAR;
    length, usernameLength: SYSTEM.CARD16;
    table: SYSTEM.INT32;
    items: ARRAY 2 OF VmsArguments.ItemListEntry3;
    iosb: VmsArguments.IOStatusBlock;
    username: ARRAY 12 OF CHAR;
    time: HUGEINT;
    memory: SYSTEM.ADDRESS;
    channel: SYSTEM.CARD16;
    fab: FABDEF.FABDEF;
    name: ARRAY 32 OF CHAR;

  (* a condition value as DCL writes one, %X and 8 digits *)
  PROCEDURE Status(text: ARRAY OF CHAR; s: LONGINT);
  BEGIN
    Out.String(text); Out.String("%X"); Out.Hex(s, 8)
  END Status;

  (* s's first n characters, in brackets, then the status *)
  PROCEDURE Show(what: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; n: SYSTEM.CARD16);
    VAR k: LONGINT;
  BEGIN
    k := SYSTEM.VAL(LONGINT, n);
    IF k < LEN(s) THEN s[k] := 0X END;
    Out.String(what); Out.String(" ["); Out.String(s); Status("] status ", status); Out.Ln
  END Show;

BEGIN
  (* LIB$ and STR$ strings by descriptor, in and out *)
  status := LIB_ROUTINES.LIB$SET_SYMBOL("POC_VMSDEF", "from poc", localSymbol);
  status := LIB_ROUTINES.LIB$GET_SYMBOL("POC_VMSDEF", value, length, table);
  Show("symbol", value, length);
  status := STR_ROUTINES.STR$UPCASE(upper, "upper case");
  Show("upcased", upper, 10);
  IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL") ; Out.Ln END;

  (* an address out, then in *)
  status := LIB_ROUTINES.LIB$GET_VM(100, memory, NIL);
  Status("get_vm status ", status); Out.Ln;
  status := LIB_ROUTINES.LIB$FREE_VM(100, memory, NIL);
  Status("free_vm status ", status); Out.Ln;

  (* item lists and an I/O status block, as ARRAY OF SYSTEM.BYTE *)
  VmsArguments.SetItem(items, 0, LNMDEF.LNM$_STRING, value, length);
  VmsArguments.EndList(items, 1);
  status := STARLET.SYS$TRNLNM(NIL, "LNM$PROCESS", "POC_VMSDEF_LNM", NIL, items);
  Show("logical name", value, length);
  VmsArguments.SetItem(items, 0, JPIDEF.JPI$_USERNAME, username, usernameLength);
  status := STARLET.SYS$GETJPIW(0, NIL, NIL, items, iosb, NIL, 0);
  Show("username", username, usernameLength);
  Status("I/O status ", SYSTEM.VAL(LONGINT, iosb.status)); Out.Ln;

  (* a quadword in, from a variable and from a constant, which poc
     passes as an 8-byte copy *)
  status := STARLET.SYS$BINTIM("14-OCT-2026 12:34:56.78", time);
  status := STARLET.SYS$ASCTIM(length, value, time, 0);
  Show("time", value, length);
  status := STARLET.SYS$ASCTIM(length, value, oneMinute, 0);
  Show("delta", value, length);

  (* a string constant as $QIOW's P1, to the null device *)
  status := STARLET.SYS$ASSIGN("NLA0:", channel, 0, NIL, 0);
  Status("assign status ", status); Out.Ln;
  status := STARLET.SYS$QIOW(0, channel, IODEF.IO$_WRITEVBLK, iosb, NIL, 0,
                             "written by SYS$QIOW", 19, 0, 0, 0, 0);
  Status("qiow status ", status); Status(", I/O status ", SYSTEM.VAL(LONGINT, iosb.status));
  Out.String(", count "); Out.Card(iosb.count, 0); Out.Ln;
  status := STARLET.SYS$DASSGN(channel);

  (* RMS with FABDEF's record: what $OPEN fills in *)
  fab.FAB$B_BID := FABDEF.FAB$C_BID; fab.FAB$B_BLN := FABDEF.FAB$C_BLN;
  name := fileName;
  fab.FAB$L_FNA := SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(name)); fab.FAB$B_FNS := 15;
  fab.FAB$B_FAC := FABDEF.FAB$M_GET;
  status := STARLET.SYS$OPEN(fab, NIL, NIL);
  Status("open status ", status); Status(", FAB$L_STS ", SYSTEM.VAL(LONGINT, fab.FAB$L_STS)); Out.Ln;
  Out.String("organization "); Out.Card(fab.FAB$B_ORG, 0);
  Out.String(", record format "); Out.Card(fab.FAB$B_RFM, 0);
  Out.String(", attributes "); Out.Card(fab.FAB$B_RAT, 0); Out.Ln;
  IF fab.FAB$W_IFI # 0 THEN Out.String("an internal file index") ; Out.Ln END;
  status := STARLET.SYS$CLOSE(fab, NIL, NIL);
  Status("close status ", status); Out.Ln;
  name := "NO_SUCH_FILE.TXT"; fab.FAB$B_FNS := 16;
  status := STARLET.SYS$OPEN(fab, NIL, NIL);
  IF status = RMSDEF.RMS$_FNF THEN Out.String("RMS$_FNF") ; Out.Ln END
END VmsDefCalls.
