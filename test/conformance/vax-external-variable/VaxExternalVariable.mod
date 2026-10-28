MODULE VaxExternalVariable;
  (* vax-external-variable (doc/developer/language-extensions.md,
     "External variables"): VaxExternalData's external variables read,
     written, passed as VAR actuals and their addresses taken, through the
     import; EXT_PAIR declared again here, writable; EXT_FLAGS, a set,
     under its own name; and EXTSHR_LIMIT, which the shareable image
     EXTSHR.EXE makes universal. Each starts at the value HAND-EXTDATA.MAR
     or HAND-EXTSHR.MAR gave it. The exit status, which DCL's $STATUS
     shows, is what the checks add up to, 42 + 39 + 78 + 101 + 9 = 269,
     times 16, plus 1: 4305, %X10D1; a failed check adds nothing. *)
  IMPORT SYSTEM, VaxExternalData;

  VAR
    ["VMS", "EXT_PAIR"] pair: VaxExternalData.Pair;
    ["VMS"] ext_flags: SET;
    ["VMS", "EXTSHR_LIMIT"] limit: LONGINT;
    i, sum, status: LONGINT;

  PROCEDURE ["VMS"] SYS$EXIT(code: LONGINT);

  PROCEDURE Bump(VAR x: LONGINT);
  BEGIN
    INC(x)
  END Bump;

BEGIN
  Bump(VaxExternalData.counter);
  status := VaxExternalData.counter;
  VaxExternalData.table[2] := 30;
  FOR i := 0 TO 1 DO Bump(VaxExternalData.table[i]) END;
  sum := 0;
  FOR i := 0 TO LEN(VaxExternalData.table) - 1 DO INC(sum, VaxExternalData.table[i]) END;
  INC(status, sum);
  pair.first := 70;
  IF SYSTEM.ADR(pair) = SYSTEM.ADR(VaxExternalData.pair) THEN
    INC(status, VaxExternalData.pair.first + VaxExternalData.pair.second)
  END;
  Bump(limit);
  INC(status, limit);
  INCL(ext_flags, 3);
  IF ext_flags = {0, 3} THEN INC(status, 9) END;
  SYS$EXIT(status * 16 + 1)
END VaxExternalVariable.
