MODULE consoleextra;
  (* PLAN.md Phase 10 step 1, the parts of Console specific to poc: the
     smallest HUGEINT, and every one beyond LONGINT (voc's own Console.Int
     goes through a LONGINT and prints a wrong number for them), a string with no terminating 0X, and a program that imports Console
     while declaring write(2) itself the way the older fixtures do - the
     backend declares the C symbol once, and both ways of writing keep
     their order. *)
  IMPORT Console;
  VAR exact: ARRAY 3 OF CHAR; h: HUGEINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  Console.Int(MIN(HUGEINT), 0); Console.Ln;
  Console.Int(MIN(HUGEINT), 25); Console.Char("|"); Console.Ln;
  Console.Int(MIN(HUGEINT) + 1, 0); Console.Ln;
  h := MAX(HUGEINT); Console.Int(h, 0); Console.Ln;
  h := 1000000; h := h * 1000000; Console.Int(h, 0); Console.Ln;
  h := -h; Console.Int(h, 20); Console.Ln;
  exact[0] := "x"; exact[1] := "y"; exact[2] := "z";
  Console.String(exact); Console.Ln;
  Console.String("one "); SysWrite(1, "two ", 4); Console.String("three"); SysWrite(1, "!", 1); Console.Ln
END consoleextra.
