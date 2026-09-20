MODULE stringsextra;
  (* PLAN.md Phase 10 step 6: rtl/llvm/Strings.Mod where poc's differs from
     voc's - strings cut short to fit, an insert past the end, a replace not
     at the start, arrays with no 0X, and numbers converted exactly (checked
     by their bits). Poc only: voc gets several of these wrong. *)
  IMPORT Strings, Out, SYSTEM;

  TYPE
    Guarded = RECORD text: ARRAY 6 OF CHAR; guard: CHAR END;

  VAR
    big: ARRAY 40000 OF CHAR;
    g: Guarded;
    long: ARRAY 700 OF CHAR;
    k: INTEGER; index: LONGINT;
    x: LONGREAL;
    r: REAL;

  PROCEDURE Show(s: ARRAY OF CHAR);
  BEGIN Out.Char("["); Out.String(s); Out.Char("]"); Out.Ln END Show;

  PROCEDURE ShowInt(i: HUGEINT);
  BEGIN Out.Int(i, 0); Out.Ln END ShowInt;

  PROCEDURE ShowGuard(VAR g: Guarded);
  BEGIN Show(g.text); Out.Char(g.guard); Out.Ln END ShowGuard;

  PROCEDURE ShowBits(x: LONGREAL);
  BEGIN ShowInt(SYSTEM.VAL(HUGEINT, x)) END ShowBits;

  PROCEDURE Truncation;
    VAR d: ARRAY 6 OF CHAR;
  BEGIN
    (* cut short to fit, the last place kept for the 0X, nothing beyond dst *)
    g.guard := "!";
    g.text := "abcd"; Strings.Insert("XYZ", 2, g.text); ShowGuard(g);
    g.text := "abc"; Strings.Insert("de", 1, g.text); ShowGuard(g);
    g.text := "abcde"; Strings.Insert("X", 0, g.text); ShowGuard(g);
    g.text := "abc"; Strings.Append("defgh", g.text); ShowGuard(g);
    g.text := "abcde"; Strings.Append("f", g.text); ShowGuard(g);
    Strings.Extract("abcdefgh", 2, 100, g.text); ShowGuard(g);
    Strings.Extract("abcdefgh", 0, 3, g.text); ShowGuard(g);
    g.text := "abcd"; Strings.Replace("1234567", 1, g.text); ShowGuard(g);
    Strings.Extract("abcdefgh", 1, 4, d); Show(d);
    (* a destination that is all string, with no room for a 0X, is left alone *)
    d[0] := "a"; d[1] := "b"; d[2] := "c"; d[3] := "d"; d[4] := "e"; d[5] := "f";
    Strings.Append("X", d); Strings.Insert("Y", 1, d);
    FOR k := 0 TO 5 DO Out.Char(d[k]) END; Out.Ln
  END Truncation;

  PROCEDURE PastTheEnd;
    VAR d: ARRAY 30 OF CHAR;
  BEGIN
    d := "abc"; Strings.Insert("XY", 9, d); Show(d);
    d := "abcdef"; Strings.Replace("XY", 1, d); Show(d);
    d := "abcdef"; Strings.Replace("XY", 4, d); Show(d);
    d := "abc"; Strings.Replace("Z", 10, d); Show(d);
    d := "abcdef"; Strings.Delete(d, -3, 2); Show(d);
    d := "abcdef"; Strings.Delete(d, 2, 0); Show(d);
    d := "abcdef"; Strings.Delete(d, 2, -2); Show(d);
    d := "abcdef"; Strings.Delete(d, 1, MAX(INTEGER)); Show(d);
    Strings.Extract("abcdef", 2, -1, d); Show(d);
    Strings.Extract("abcdef", -5, 2, d); Show(d);
    Out.Int(Strings.Pos("a", "abc", -5), 0); Out.Ln;
    Out.Int(Strings.Pos("c", "abcabc", 3), 0); Out.Ln;
    Out.Int(Strings.Pos("", "abc", 2), 0); Out.Ln
  END PastTheEnd;

  PROCEDURE NoTerminator;
    VAR t: Guarded;
  BEGIN
    (* no 0X in the array: its length is its size, and nothing reads past it *)
    t.guard := "z";
    FOR k := 0 TO 5 DO t.text[k] := "q" END;
    Out.Int(Strings.Length(t.text), 0); Out.Ln;
    Strings.Cap(t.text);
    FOR k := 0 TO 5 DO Out.Char(t.text[k]) END; Out.Char(t.guard); Out.Ln;
    Out.Int(Strings.Pos("QQ", t.text, 0), 0); Out.Ln;
    Out.Int(Strings.Pos("Qz", t.text, 0), 0); Out.Ln;
    Out.Int(Strings.Pos("QQQQQQQ", t.text, 0), 0); Out.Ln;
    FOR index := 0 TO LEN(big) - 1 DO big[index] := "x" END;
    Out.Int(Strings.Length(big), 0); Out.Ln;
    Out.Int(MAX(INTEGER), 0); Out.Ln
  END NoTerminator;

  PROCEDURE Yes(s, pattern: ARRAY OF CHAR);
  BEGIN
    Out.String(s); Out.Char(" "); Out.String(pattern); Out.Char(" ");
    IF Strings.Match(s, pattern) THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END Yes;

  PROCEDURE MoreMatches;
  BEGIN
    Yes("aab", "*ab");
    Yes("ababab", "*abab");
    Yes("mississippi", "m*iss*ppi");
    Yes("mississippi", "m*iss*ppx");
    Yes("mississippi", "*ss*ss*");
    Yes("mississippi", "*ss*ss*ss*");
    Yes("", "***");
    Yes("a", "***");
    Yes("abc", "abc*");
    Yes("abc", "*abcd");
    Yes("a*c", "a*c");
    Yes("axxxxb", "a*b*")
  END MoreMatches;

  PROCEDURE Numbers;
  BEGIN
    (* the nearest number, not a sum of roundings: 0.1 is 3FB999999999999A *)
    Strings.StrToLongReal("0.1", x); ShowBits(x);
    Strings.StrToLongReal("1.7976931348623157E308", x); ShowBits(x);
    Strings.StrToLongReal("4.9E-324", x); ShowBits(x);
    Strings.StrToLongReal("123456789012345678901234567890", x); ShowBits(x);
    Strings.StrToLongReal("2.2250738585072014D-308", x); ShowBits(x);
    Strings.StrToReal("0.1", r); ShowInt(SYSTEM.VAL(LONGINT, r));
    (* the shape of a numeral: blanks, a sign, either case, what follows *)
    Strings.StrToLongReal("  +7.25e1x", x); ShowBits(x);
    Strings.StrToLongReal("  -7.25E+1", x); ShowBits(x);
    Strings.StrToLongReal("1e", x); ShowBits(x);
    Strings.StrToLongReal("1.5e+", x); ShowBits(x);
    Strings.StrToLongReal("1.5d3d", x); ShowBits(x);
    Strings.StrToLongReal(".5", x); ShowBits(x);
    Strings.StrToLongReal("5.", x); ShowBits(x);
    Strings.StrToLongReal("5.e2", x); ShowBits(x);
    Strings.StrToLongReal("1 2", x); ShowBits(x);
    Strings.StrToLongReal("0x10", x); ShowBits(x);
    x := 42;
    Strings.StrToLongReal("-", x); ShowBits(x);
    x := 42;
    Strings.StrToLongReal(".", x); ShowBits(x);
    x := 42;
    Strings.StrToLongReal("e5", x); ShowBits(x);
    x := 42;
    Strings.StrToLongReal("inf", x); ShowBits(x);
    (* a numeral too long for the conversion buffer changes nothing *)
    FOR k := 0 TO 598 DO long[k] := "1" END;
    long[599] := 0X;
    x := 42;
    Strings.StrToLongReal(long, x); ShowBits(x);
    r := 7;
    Strings.StrToReal(long, r); Out.Real(r, 8); Out.Ln
  END Numbers;

BEGIN
  Truncation;
  PastTheEnd;
  NoTerminator;
  MoreMatches;
  Numbers
END stringsextra.
