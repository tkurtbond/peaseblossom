MODULE modulesextra;
  (* PLAN.md Phase 10 step 4, the parts of Modules specific to poc: an
     argument number outside the range gives "" (voc leaves the value as it
     was), and an argument longer than a page is read whole or cut to fit.
     It is started with two arguments: one of 3000 zeros, and "b". Each
     check prints its number and ok or FAIL. *)
  IMPORT Modules, Console;
  VAR
    value: ARRAY 16 OF CHAR;
    big: ARRAY 4000 OF CHAR;
    length: INTEGER;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Console.Int(number, 2); Console.Char(" ");
    IF ok THEN Console.String("ok") ELSE Console.String("FAIL") END;
    Console.Ln
  END Check;

BEGIN
  Check(1, Modules.ArgCount = 3);
  Check(2, Modules.ArgVector # 0);

  (* 3-5: outside the range *)
  value := "junk";
  Modules.GetArg(Modules.ArgCount, value);
  Check(3, value[0] = 0X);
  value := "junk";
  Modules.GetArg(-1, value);
  Check(4, value[0] = 0X);
  value := "junk";
  Modules.GetArg(MAX(INTEGER), value);
  Check(5, value[0] = 0X);

  (* 6-8: a long argument *)
  Modules.GetArg(1, value);
  Check(6, (value = "000000000000000") & (LEN(value) = 16));
  Modules.GetArg(1, big);
  length := 0;
  WHILE (length < LEN(big)) & (big[length] = "0") DO INC(length) END;
  Check(7, (length = 3000) & (big[length] = 0X));
  Modules.GetArg(2, value);
  Check(8, value = "b")
END modulesextra.
