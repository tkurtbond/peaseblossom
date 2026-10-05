MODULE outstr;
  (* OutStr (PLAN.md, "Ongoing library enhancements" 1): each case is
     written by Out, then by OutStr into a string that Out writes; the two
     lines must be the same (test.sh checks). Then appending to a string
     that holds text, and truncation at every length of a short one. *)
  IMPORT SYSTEM, Out, OutStr;
  VAR
    s: ARRAY 128 OF CHAR;
    bits32: SYSTEM.INT32; bits64: HUGEINT; r: REAL; x: LONGREAL;
    s1: ARRAY 1 OF CHAR; s2: ARRAY 2 OF CHAR; s3: ARRAY 3 OF CHAR; s4: ARRAY 4 OF CHAR;
    s5: ARRAY 5 OF CHAR; s6: ARRAY 6 OF CHAR; s7: ARRAY 7 OF CHAR; s8: ARRAY 8 OF CHAR;
    full: ARRAY 4 OF CHAR;

  PROCEDURE Show; BEGIN Out.Char("|"); Out.Ln; Out.String(s); Out.Char("|"); Out.Ln; s := "" END Show;

  PROCEDURE Int(x, n: HUGEINT); BEGIN Out.Int(x, n); OutStr.Int(x, n, s); Show END Int;
  PROCEDURE Hex(x, n: HUGEINT); BEGIN Out.Hex(x, n); OutStr.Hex(x, n, s); Show END Hex;
  PROCEDURE Real(x: REAL; n: INTEGER); BEGIN Out.Real(x, n); OutStr.Real(x, n, s); Show END Real;
  PROCEDURE LongReal(x: LONGREAL; n: INTEGER); BEGIN Out.LongReal(x, n); OutStr.LongReal(x, n, s); Show END LongReal;

  (* -12345 appended to "ab" in t, its text then shown with its length *)
  PROCEDURE Cut(VAR t: ARRAY OF CHAR);
    VAR k: LONGINT;
  BEGIN
    COPY("ab", t); OutStr.Int(-12345, 0, t);
    k := 0; WHILE t[k] # 0X DO INC(k) END;
    Out.Int(LEN(t), 0); Out.String(": "); Out.String(t); Out.Int(k, 2); Out.Ln
  END Cut;

BEGIN
  s := "";
  Out.Char("a"); OutStr.Char("a", s); Show;
  Out.String("a string"); OutStr.String("a string", s); Show;
  Out.String(""); OutStr.String("", s); Show;
  Int(0, 0); Int(7, 1); Int(-7, 2); Int(123, 2); Int(123, 3); Int(123, 6); Int(-5, -3);
  Int(MAX(HUGEINT), 0); Int(MIN(HUGEINT), 0); Int(MIN(HUGEINT), 25); Int(2147483647, 12);
  Hex(0, 1); Hex(255, 0); Hex(255, 4); Hex(-1, 4); Hex(-1, 16); Hex(-1, 20); Hex(MIN(HUGEINT), 16); Hex(4096, 2);
  Real(0.0, 0); Real(1.0, 0); Real(3.14159, 12); Real(-3.14159, 12); Real(1.0E30, 15); Real(-2.5E-10, 3);
  Real(123456789.0, 20);
  bits32 := 1; r := SYSTEM.VAL(REAL, bits32); Real(r, 14); (* the smallest subnormal *)
  bits32 := 7F800000H; r := SYSTEM.VAL(REAL, bits32); Real(r, 10); Real(-r, 10); (* infinities *)
  bits32 := 7FC00000H; r := SYSTEM.VAL(REAL, bits32); Real(r, 6); (* NaN *)
  LongReal(0.0D0, 0); LongReal(1.0D0, 0); LongReal(-2.5D-300, 0); LongReal(1.0D0 / 3.0D0, 25);
  LongReal(6.02214076D23, 30);
  bits64 := 1; x := SYSTEM.VAL(LONGREAL, bits64); LongReal(x, 24);
  bits64 := 7FF0000000000000H; x := SYSTEM.VAL(LONGREAL, bits64); LongReal(x, 10); LongReal(-x, 10);
  bits64 := 7FF8000000000000H; x := SYSTEM.VAL(LONGREAL, bits64); LongReal(x, 6);
  Out.String("x="); Out.Int(42, 5); Out.Hex(42, 2);
  OutStr.String("x=", s); OutStr.Int(42, 5, s); OutStr.Hex(42, 2, s); Show;
  (* Ln appends a line feed, as Out.Ln writes one *)
  s := "line"; OutStr.Ln(s); Out.Int(ORD(s[4]), 0); Out.Int(ORD(s[5]), 3); Out.Ln;

  (* appending to a string that already holds text *)
  s := "count: "; OutStr.Int(3, 0, s); OutStr.Char(";", s); OutStr.Real(0.5, 10, s);
  Out.String(s); Out.Ln;
  (* a string onto itself *)
  s := "echo "; OutStr.String(s, s); Out.String(s); Out.Ln;
  (* cut short at every length *)
  Cut(s1); Cut(s2); Cut(s3); Cut(s4); Cut(s5); Cut(s6); Cut(s7); Cut(s8);
  (* a string with no 0X: its last character gives way to one *)
  full[0] := "w"; full[1] := "x"; full[2] := "y"; full[3] := "z";
  OutStr.Char("!", full); Out.String(full); Out.Ln;
  s := "pad"; OutStr.Int(1, 200, s); s[20] := 0X; Out.String(s); Out.Char("|"); Out.Ln
END outstr.
