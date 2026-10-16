MODULE ChainedUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 11): run by
     SpawnUse's LIB$RUN_PROGRAM; prints what SpawnUse put in the common
     area (LIB$GET_COMMON), and ends by LIB$DO_COMMAND. *)
  IMPORT SYSTEM, Out, LIB_ROUTINES;

  VAR
    text: ARRAY 256 OF CHAR;
    length: SYSTEM.CARD16;
    status: SYSTEM.INT32;
    n: LONGINT;

BEGIN
  length := 0;
  status := LIB_ROUTINES.LIB$GET_COMMON(text, length);
  n := SYSTEM.VAL(SYSTEM.INT32, length);
  IF n > LEN(text) - 1 THEN n := LEN(text) - 1 END;
  text[n] := 0X;
  Out.String("ChainedUse: LIB$GET_COMMON status %X"); Out.Hex(status, 8);
  Out.String(", |"); Out.String(text); Out.String("|"); Out.Ln;
  Out.String("ChainedUse ends by LIB$DO_COMMAND"); Out.Ln;
  status := LIB_ROUTINES.LIB$DO_COMMAND('WRITE SYS$OUTPUT "from LIB$DO_COMMAND"');
  Out.String("ChainedUse: LIB$DO_COMMAND returned %X"); Out.Hex(status, 8); Out.Ln
END ChainedUse.
