MODULE consoletest;
  (* PLAN.md Phase 10 step 1: rtl/llvm/Console.Mod, the module every later
     runtime module can print through. Everything here is the part of the
     interface poc's Console shares with voc's own, so test.sh runs this same
     source under both compilers and requires identical output. *)
  IMPORT Console;
  VAR
    text: ARRAY 8 OF CHAR;
    i: INTEGER;
    l: LONGINT;
BEGIN
  (* String and Ln *)
  Console.String("Hello, Peaseblossom!"); Console.Ln;
  Console.String(""); Console.Ln;
  text := "abc";
  Console.String(text); Console.String(text); Console.Ln;
  Console.String("no newline yet, "); Console.String("still the same line"); Console.Ln;

  (* Char *)
  Console.Char("x"); Console.Char("y"); Console.Char(" "); Console.Char("z"); Console.Ln;

  (* Int: sign, zero, field widths (none, exact, wider, narrower), the
     extremes of each type up to LONGINT (voc's Console.Int goes
     through a LONGINT, so a wider value is consoleextra's) *)
  Console.Int(0, 0); Console.Ln;
  Console.Int(7, 1); Console.Char("|"); Console.Ln;
  Console.Int(-7, 0); Console.Ln;
  Console.Int(1234, 0); Console.Ln;
  Console.Int(-1234, 8); Console.Char("|"); Console.Ln;
  Console.Int(1234, 2); Console.Ln;
  Console.Int(5, 40); Console.Char("|"); Console.Ln;
  Console.Int(5, 70); Console.Char("|"); Console.Ln;
  i := MAX(INTEGER); Console.Int(i, 0); Console.Ln;
  i := MIN(INTEGER); Console.Int(i, 0); Console.Ln;
  l := MAX(LONGINT); Console.Int(l, 0); Console.Ln;
  l := MIN(LONGINT); Console.Int(l, 0); Console.Ln;

  (* Hex: always every digit, negative numbers as two's complement *)
  Console.Hex(0); Console.Ln;
  Console.Hex(255); Console.Ln;
  Console.Hex(3054CDEFH); Console.Ln;
  Console.Hex(-1); Console.Ln;
  Console.Hex(MIN(LONGINT)); Console.Ln;

  (* Bool *)
  Console.Bool(TRUE); Console.Char(" "); Console.Bool(FALSE); Console.Ln;

  (* Flush is always safe to call *)
  Console.Flush;
  Console.String("done"); Console.Ln
END consoletest.
