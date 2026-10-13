MODULE ArgVector;
  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.5, proposal 8): Modules' ArgVector read as C's argv, each argument
     compared with what GetArg gives; BinaryDir, the image's device and
     directory, which argument 0 starts with, the image's name and version
     after it; MainStackFrame, an address in P1 space, where the stack is *)
  IMPORT SYSTEM, Modules, Out;
  VAR
    i, k: INTEGER; address: SYSTEM.ADDRESS; ch: CHAR; same: BOOLEAN;
    arg: ARRAY 1024 OF CHAR;
BEGIN
  Out.String("count "); Out.Int(Modules.ArgCount, 0); Out.Ln;
  FOR i := 0 TO Modules.ArgCount - 1 DO
    SYSTEM.GET(Modules.ArgVector + i * SIZE(SYSTEM.ADDRESS), address);
    Modules.GetArg(i, arg);
    k := 0; same := TRUE;
    SYSTEM.GET(address, ch);
    WHILE ch # 0X DO
      IF arg[k] # ch THEN same := FALSE END;
      INC(k); SYSTEM.GET(address + k, ch)
    END;
    Out.Int(i, 0);
    IF same & (arg[k] = 0X) THEN Out.String(" as GetArg") ELSE Out.String(" DIFFERS") END;
    IF i > 0 THEN Out.String(" ["); Out.String(arg); Out.String("]") END;
    Out.Ln
  END;
  Modules.GetArg(0, arg);
  k := 0;
  WHILE (Modules.BinaryDir[k] # 0X) & (Modules.BinaryDir[k] = arg[k]) DO INC(k) END;
  Out.String("BinaryDir ends in ]: ");
  IF (k > 0) & (Modules.BinaryDir[k] = 0X) & (Modules.BinaryDir[k - 1] = "]") THEN Out.String("yes") ELSE Out.String("no") END;
  Out.Ln;
  Out.String("after it: ");
  WHILE arg[k] # 0X DO Out.Char(arg[k]); INC(k) END;
  Out.Ln;
  Out.String("MainStackFrame in P1: ");
  IF Modules.MainStackFrame >= 40000000H THEN Out.String("yes") ELSE Out.String("no") END;
  Out.Ln
END ArgVector.
