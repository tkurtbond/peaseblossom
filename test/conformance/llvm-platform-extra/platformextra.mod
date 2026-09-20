MODULE platformextra;
  (* PLAN.md Phase 10 step 2, the parts of Platform specific to poc: PID
     is the real process id (the shell's own idea of its parent's id,
     reduced the way PID is when it does not fit an INTEGER), an error is
     -1 rather than voc's errno, and a string with no terminating 0X is
     treated as naming nothing instead of being read past its end. Each
     check prints its number and ok or FAIL. *)
  IMPORT Platform, Console;
  VAR
    exact: ARRAY 4 OF CHAR;
    missing: ARRAY 8 OF CHAR;
    single: ARRAY 1 OF CHAR;
    value: ARRAY 16 OF CHAR;
    command: ARRAY 64 OF CHAR;
    digits: ARRAY 8 OF CHAR;
    id, n, k: INTEGER;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Console.Int(number, 2); Console.Char(" ");
    IF ok THEN Console.String("ok") ELSE Console.String("FAIL") END;
    Console.Ln
  END Check;

BEGIN
  (* 1-3: PID, and the working directory found at startup *)
  Check(1, Platform.PID > 0);
  (* "test $(( $PPID % 32768 )) -eq <PID>", the pid the shell System
     starts was given as its parent: this process *)
  command := "test $(( $PPID % 32768 )) -eq ";
  id := Platform.PID; n := 0;
  REPEAT digits[n] := CHR(ORD("0") + id MOD 10); id := id DIV 10; INC(n) UNTIL id = 0;
  k := 0;
  WHILE command[k] # 0X DO INC(k) END;
  WHILE n > 0 DO DEC(n); command[k] := digits[n]; INC(k) END;
  command[k] := 0X;
  Check(2, Platform.System(command) = 0);
  Check(3, Platform.CWD[0] = "/");

  (* 4-5: an error is -1 *)
  missing := "nope";
  Check(4, Platform.Unlink(missing) = -1);
  Check(5, Platform.Chdir(missing) = -1);

  (* 6-8: a string with no terminator is not read past its end: 4 letters
     in an array of 4, one that would name a real command *)
  exact[0] := "t"; exact[1] := "r"; exact[2] := "u"; exact[3] := "e";
  Platform.GetEnv(exact, value);
  Check(6, value[0] = 0X);
  Check(7, Platform.System(exact) = -1);
  Check(8, Platform.Unlink(exact) = -1);
  (* 9: a value array with room for the terminator only *)
  Platform.GetEnv("HOME", single);
  Check(9, single[0] = 0X)
END platformextra.
