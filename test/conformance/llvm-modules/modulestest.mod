MODULE modulestest;
  (* PLAN.md Phase 10 step 4: rtl/llvm/Modules.Mod - the command line,
     through the part of the interface poc's Modules shares with voc's
     own (test.sh runs this same source under both and requires the same
     output). It is started with the arguments  alpha  "two words"  ""
     42  -7  and prints each of them - but not argument 0, the program's
     own name, which differs from one compiler to the next. Each check
     prints its number and ok or FAIL. *)
  IMPORT Modules, Console;
  VAR
    i: INTEGER;
    arg: ARRAY 64 OF CHAR;
    small: ARRAY 4 OF CHAR;
    number: LONGINT;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Console.Int(number, 2); Console.Char(" ");
    IF ok THEN Console.String("ok") ELSE Console.String("FAIL") END;
    Console.Ln
  END Check;

BEGIN
  Console.String("arguments: "); Console.Int(Modules.ArgCount, 0); Console.Ln;
  FOR i := 1 TO Modules.ArgCount - 1 DO
    Modules.GetArg(i, arg);
    Console.Int(i, 2); Console.String(": ["); Console.String(arg); Console.Char("]"); Console.Ln
  END;

  (* 1-2: argument 0 is there *)
  Modules.GetArg(0, arg);
  Check(1, arg[0] # 0X);
  Check(2, Modules.ArgCount = 6);

  (* 3-4: a value too small for the argument gets the start of it *)
  Modules.GetArg(2, small);
  Check(3, small = "two");
  Modules.GetArg(3, small);
  Check(4, small = "");

  (* 5-6: where an argument is *)
  Check(5, Modules.ArgPos("alpha") = 1);
  Check(6, Modules.ArgPos("not among them") = Modules.ArgCount);

  (* 7-10: arguments as numbers, and one that is not a number *)
  number := 1000;
  Modules.GetIntArg(4, number);
  Check(7, number = 42);
  Modules.GetIntArg(5, number);
  Check(8, number = -7);
  number := 1000;
  Modules.GetIntArg(1, number);
  Check(9, number = 1000);
  Modules.GetIntArg(3, number);
  Check(10, number = 1000)
END modulestest.
