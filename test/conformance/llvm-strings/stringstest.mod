MODULE stringstest;
  (* PLAN.md Phase 10 step 6: rtl/llvm/Strings.Mod - what poc's Strings
     shares with voc's own, on cases where voc's is right (test.sh runs this
     same source under both and requires the same output; llvm-strings-extra
     has the cases voc gets wrong, and truncation). Numbers are read only in
     forms voc's digit-by-digit conversion also gets exactly. *)
  IMPORT Strings, Out;

  PROCEDURE Show(s: ARRAY OF CHAR);
  BEGIN Out.Char("["); Out.String(s); Out.Char("]"); Out.Ln END Show;

  PROCEDURE ShowBool(b: BOOLEAN);
  BEGIN IF b THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln END ShowBool;

  PROCEDURE ShowInt(i: LONGINT);
  BEGIN Out.Int(i, 0); Out.Ln END ShowInt;

  PROCEDURE Lengths;
    VAR big: ARRAY 20 OF CHAR; exact: ARRAY 3 OF CHAR;
  BEGIN
    ShowInt(Strings.Length(""));
    ShowInt(Strings.Length("abc"));
    big := "hello"; ShowInt(Strings.Length(big));
    exact := "ab"; ShowInt(Strings.Length(exact))
  END Lengths;

  PROCEDURE Inserts;
    VAR d: ARRAY 30 OF CHAR;
  BEGIN
    d := "hellorld"; Strings.Insert(" wo", 5, d); Show(d);
    d := "world"; Strings.Insert("hello ", 0, d); Show(d);
    d := "hello"; Strings.Insert(" world", 5, d); Show(d);
    d := ""; Strings.Insert("abc", 0, d); Show(d);
    d := "abc"; Strings.Insert("", 1, d); Show(d);
    d := "abc"; Strings.Insert("XY", -4, d); Show(d)
  END Inserts;

  PROCEDURE Appends;
    VAR d: ARRAY 30 OF CHAR;
  BEGIN
    d := "abc"; Strings.Append("def", d); Show(d);
    d := ""; Strings.Append("xyz", d); Show(d);
    d := "abc"; Strings.Append("", d); Show(d);
    d := "one"; Strings.Append(", two", d); Strings.Append(", three", d); Show(d)
  END Appends;

  PROCEDURE Deletes;
    VAR s: ARRAY 30 OF CHAR;
  BEGIN
    s := "abcdefgh"; Strings.Delete(s, 2, 3); Show(s);
    s := "abcdefgh"; Strings.Delete(s, 0, 2); Show(s);
    s := "abcdefgh"; Strings.Delete(s, 5, 3); Show(s);
    s := "abcdefgh"; Strings.Delete(s, 5, 100); Show(s);
    s := "abcdefgh"; Strings.Delete(s, 8, 1); Show(s);
    s := "abcdefgh"; Strings.Delete(s, 20, 1); Show(s);
    s := "abcdefgh"; Strings.Delete(s, 0, 8); Show(s)
  END Deletes;

  PROCEDURE Replaces;
    VAR d: ARRAY 30 OF CHAR;
  BEGIN
    d := "abcdef"; Strings.Replace("XY", 0, d); Show(d);
    d := "abcdef"; Strings.Replace("", 0, d); Show(d);
    d := "abc"; Strings.Replace("longer text", 0, d); Show(d)
  END Replaces;

  PROCEDURE Extracts;
    VAR d: ARRAY 30 OF CHAR;
  BEGIN
    Strings.Extract("hello world", 6, 5, d); Show(d);
    Strings.Extract("hello world", 0, 5, d); Show(d);
    Strings.Extract("hello world", 6, 100, d); Show(d);
    Strings.Extract("hello world", 11, 3, d); Show(d);
    Strings.Extract("hello world", 40, 3, d); Show(d);
    Strings.Extract("hello world", 3, 0, d); Show(d)
  END Extracts;

  PROCEDURE Positions;
  BEGIN
    ShowInt(Strings.Pos("lo", "hello world", 0));
    ShowInt(Strings.Pos("o", "hello world", 0));
    ShowInt(Strings.Pos("o", "hello world", 5));
    ShowInt(Strings.Pos("hello", "hello world", 0));
    ShowInt(Strings.Pos("world", "hello world", 0));
    ShowInt(Strings.Pos("xyz", "hello world", 0));
    ShowInt(Strings.Pos("world", "hello world", 7));
    ShowInt(Strings.Pos("a longer pattern", "short", 0));
    ShowInt(Strings.Pos("", "anything", 0))
  END Positions;

  PROCEDURE Caps;
    VAR s: ARRAY 30 OF CHAR;
  BEGIN
    s := "Hello, World 42!"; Strings.Cap(s); Show(s);
    s := "already UPPER"; Strings.Cap(s); Show(s);
    s := ""; Strings.Cap(s); Show(s)
  END Caps;

  PROCEDURE Matches;
  BEGIN
    ShowBool(Strings.Match("hello", "hello"));
    ShowBool(Strings.Match("hello", "hell"));
    ShowBool(Strings.Match("hello", "hello!"));
    ShowBool(Strings.Match("hello", "h*"));
    ShowBool(Strings.Match("hello", "*o"));
    ShowBool(Strings.Match("hello", "*"));
    ShowBool(Strings.Match("", "*"));
    ShowBool(Strings.Match("", ""));
    ShowBool(Strings.Match("hello", ""));
    ShowBool(Strings.Match("hello", "h*l*o"));
    ShowBool(Strings.Match("hello", "h*x*o"));
    ShowBool(Strings.Match("main.mod", "*.mod"));
    ShowBool(Strings.Match("main.mod.bak", "*.mod"));
    ShowBool(Strings.Match("abcabc", "*abc"));
    ShowBool(Strings.Match("aXbXc", "a*b*c"));
    ShowBool(Strings.Match("abc", "a**c"));
    ShowBool(Strings.Match("ac", "a*c"));
    ShowBool(Strings.Match("acb", "a*c"))
  END Matches;

  PROCEDURE Numbers;
    VAR r: REAL; x: LONGREAL;
  BEGIN
    Strings.StrToReal("1.5", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("-2.5", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("100", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("1E3", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("2.5D2", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("12.5xyz", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("0.5E-1", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToReal("abc", r); Out.Real(r, 10); Out.Ln;
    Strings.StrToLongReal("1.5", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("-2.5", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("100", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("1E3", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("2.5D2", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("12.5 and more", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("0.5E-1", x); Out.LongReal(x, 16); Out.Ln;
    Strings.StrToLongReal("", x); Out.LongReal(x, 16); Out.Ln
  END Numbers;

BEGIN
  Lengths;
  Inserts;
  Appends;
  Deletes;
  Replaces;
  Extracts;
  Positions;
  Caps;
  Matches;
  Numbers
END stringstest.
