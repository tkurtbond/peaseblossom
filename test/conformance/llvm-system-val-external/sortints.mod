MODULE sortints;
  (* An external procedure's address by SYSTEM.VAL, from the module that
     declares it and from one that imports it, passed to C's qsort *)
  IMPORT SYSTEM, Compare, Out;

  TYPE Proper = PROCEDURE;

  VAR
    numbers: ARRAY 8 OF SYSTEM.INT32;
    i: INTEGER;
    oberon: SYSTEM.ADDRESS;
    p: Proper;

  PROCEDURE ["C", "abs"] CAbs(x: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Hello;
  BEGIN Out.String("Hello, by its address"); Out.Ln
  END Hello;

BEGIN
  numbers[0] := 42; numbers[1] := -7; numbers[2] := 1000; numbers[3] := 0;
  numbers[4] := -300; numbers[5] := 7; numbers[6] := 42; numbers[7] := 1;
  Compare.Sort(SYSTEM.ADR(numbers), LEN(numbers), SIZE(SYSTEM.INT32),
               SYSTEM.VAL(SYSTEM.ADDRESS, Compare.Integers));
  FOR i := 0 TO LEN(numbers) - 1 DO Out.Int(numbers[i], 0); Out.Char(" ") END;
  Out.Ln;
  IF SYSTEM.VAL(SYSTEM.ADDRESS, Compare.Integers) = Compare.IntegersAddress() THEN
    Out.String("the same address from either module")
  ELSE
    Out.String("different addresses")
  END;
  Out.Ln;
  IF SYSTEM.VAL(SYSTEM.ADDRESS, CAbs) # 0 THEN Out.String("abs has an address") END;
  Out.Ln;
  (* an Oberon procedure's address, as before, and back *)
  oberon := SYSTEM.VAL(SYSTEM.ADDRESS, Hello);
  p := SYSTEM.VAL(Proper, oberon); p
END sortints.
