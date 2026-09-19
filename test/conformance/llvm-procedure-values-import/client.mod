MODULE client;
  (* Procedure values across a module boundary: an imported procedure
     assigned to a local variable and to the library's own variable, passed
     to an imported procedure that calls it, a procedure of this module
     handed to the library, and the library's own values called from here.
     Prints "FAIL nn " for each failed check, then "OK". *)
  IMPORT Calc;
  VAR
    f: Calc.Op;
    local: Calc.Table;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR msg: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      msg[0] := "F"; msg[1] := "A"; msg[2] := "I"; msg[3] := "L"; msg[4] := " ";
      msg[5] := CHR(ORD("0") + number DIV 10); msg[6] := CHR(ORD("0") + number MOD 10);
      msg[7] := " "; msg[8] := 0X;
      SysWrite(1, msg, 8)
    END
  END Check;

  PROCEDURE Sub(a, b: INTEGER): INTEGER;
  BEGIN RETURN a - b END Sub;

BEGIN
  f := Calc.Mul;
  Check(1, f(6, 7) = 42);
  Check(2, Calc.Apply(Calc.Add, 40, 2) = 42);
  Check(3, Calc.Apply(f, 3, 5) = 15);
  Check(4, Calc.Apply(Sub, 50, 8) = 42);
  (* the library's own variable, as it was left by its module body *)
  Check(5, Calc.current(1, 2) = 3);
  Check(6, Calc.Call(4, 5) = 9);
  Calc.Use(Calc.Mul);
  Check(7, Calc.Call(4, 5) = 20);
  Calc.current := Sub;
  Check(8, Calc.Call(4, 5) = -1);
  Calc.current := f;
  Check(9, Calc.Call(6, 7) = 42);
  (* a record of them *)
  Check(10, Calc.table.add(2, 3) + Calc.table.mul(2, 3) = 11);
  local := Calc.table;
  local.add := Sub;
  Check(11, (local.add(9, 1) = 8) & (Calc.table.add(9, 1) = 10));
  SysWrite(1, "OK", 2)
END client.
