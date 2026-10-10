MODULE ArgsOut;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 6): the arguments Modules gives, each in brackets, with
     argument 0's file name alone, and what GetArg gives for an argument
     there is not and in an array too small *)
  IMPORT Modules, Out;
  VAR i: INTEGER; arg: ARRAY 64 OF CHAR; small: ARRAY 4 OF CHAR;

  (* s after its last "/" or "]": the file's name *)
  PROCEDURE FileName(VAR s: ARRAY OF CHAR);
    VAR i, start: INTEGER;
  BEGIN
    i := 0; start := 0;
    WHILE s[i] # 0X DO
      IF (s[i] = "/") OR (s[i] = "]") THEN start := i + 1 END;
      INC(i)
    END;
    i := start;
    WHILE s[i] # 0X DO Out.Char(s[i]); INC(i) END
  END FileName;

BEGIN
  Out.String("count "); Out.Int(Modules.ArgCount, 0); Out.Ln;
  Modules.GetArg(0, arg); Out.String("0 "); FileName(arg); Out.Ln;
  FOR i := 1 TO Modules.ArgCount - 1 DO
    Modules.GetArg(i, arg); Out.Int(i, 0); Out.String(" ["); Out.String(arg); Out.String("]"); Out.Ln
  END;
  Modules.GetArg(Modules.ArgCount, arg); Out.String("past the end ["); Out.String(arg); Out.String("]"); Out.Ln;
  Modules.GetArg(-1, arg); Out.String("before the start ["); Out.String(arg); Out.String("]"); Out.Ln;
  Modules.GetArg(2, small); Out.String("cut short ["); Out.String(small); Out.String("]"); Out.Ln
END ArgsOut.
