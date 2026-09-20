MODULE Modules;

  (* PLAN.md Phase 10 step 4: access to the command line, the part of voc's
     Modules module (src/runtime/Modules.Mod) a program that is not an
     Oberon System needs: ArgCount, ArgVector, GetArg, GetIntArg, ArgPos. Not
     here: voc's list of loaded modules and commands (ThisMod, ThisCommand,
     Free - the dynamic loading of Oberon2.pdf Appendix D2, which a
     compiled program has no use for), BinaryDir, and MainStackFrame.

     A program that contains this module has a `main` that takes argc and
     argv and passes both to Init before any module body runs
     (LLVMCodeGenerator.GenerateProgram, the same pattern as the stack
     base it hands the collector); a program that does not contain it has
     an argument-less `main`. Init is exported because the generated code
     calls it, not to be called by a program: a second call would replace
     the arguments.

     Arguments are numbered as in C: 0 is the program's own name as it
     was started, 1 the first argument, ArgCount the number of them all.
     Where this differs from voc's: GetArg with n outside 0..ArgCount-1
     sets val to "" where voc leaves val as it was, so a caller that
     ignores ArgCount never sees the previous argument again as this
     one. *)

  IMPORT SYSTEM;

  VAR
    ArgCount-: INTEGER;
    ArgVector-: SYSTEM.ADDRESS; (* argv: the address of an array of ArgCount strings' addresses *)

  (* Records the command line. Called once, by the program's `main`. *)
  PROCEDURE Init*(argc, argv: SYSTEM.ADDRESS);
  BEGIN
    IF argc > MAX(INTEGER) THEN ArgCount := MAX(INTEGER)
    ELSIF argc < 0 THEN ArgCount := 0
    ELSE ArgCount := SYSTEM.VAL(INTEGER, argc)
    END;
    ArgVector := argv
  END Init;

  (* Argument n in val, cut short if val is too small for it. *)
  PROCEDURE GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR);
    VAR text: SYSTEM.ADDRESS; k: LONGINT; ch: CHAR;
  BEGIN
    IF LEN(val) = 0 THEN RETURN END;
    val[0] := 0X;
    IF (n >= 0) & (n < ArgCount) THEN
      SYSTEM.GET(ArgVector + LONG(n) * SIZE(SYSTEM.ADDRESS), text);
      k := 0;
      SYSTEM.GET(text, ch);
      WHILE (ch # 0X) & (k < LEN(val) - 1) DO
        val[k] := ch;
        INC(k);
        SYSTEM.GET(text + k, ch)
      END;
      val[k] := 0X
    END
  END GetArg;

  (* Argument n as a number - an optional minus sign and decimal digits;
     val is left alone if it does not start with a digit (after the sign).
     Same as voc's. *)
  PROCEDURE GetIntArg*(n: INTEGER; VAR val: LONGINT);
    VAR s: ARRAY 64 OF CHAR; k, d, i: LONGINT;
  BEGIN
    GetArg(n, s);
    i := 0;
    IF s[0] = "-" THEN i := 1 END;
    k := 0;
    d := ORD(s[i]) - ORD("0");
    WHILE (d >= 0) & (d <= 9) DO
      k := k * 10 + d;
      INC(i);
      d := ORD(s[i]) - ORD("0")
    END;
    IF s[0] = "-" THEN k := -k; DEC(i) END;
    IF i > 0 THEN val := k END
  END GetIntArg;

  (* The number of the first argument (from 0) equal to s, ArgCount if
     none is. *)
  PROCEDURE ArgPos*(s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
  BEGIN
    i := 0;
    GetArg(i, arg);
    WHILE (i < ArgCount) & (s # arg) DO
      INC(i);
      GetArg(i, arg)
    END;
    RETURN i
  END ArgPos;

END Modules.
