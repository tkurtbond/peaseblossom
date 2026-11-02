MODULE cardinal;
  (* The predeclared unsigned types, with no import of SYSTEM: their widths,
     under the size model the test gives, and what the rules of the
     SYSTEM.CARDn make of them. *)
  IMPORT Out;

  TYPE
    Small = RECORD a: CHAR; b: SHORTCARD; c: CARDINAL; d: LONGCARD; e: HUGECARD END;
  VAR
    sc: SHORTCARD; ca: CARDINAL; lc: LONGCARD; hc: HUGECARD;
    i, n: INTEGER; r: LONGREAL;
    arr: ARRAY 8 OF INTEGER;
    small: Small; many: ARRAY 3 OF CARDINAL;

  PROCEDURE Show(name: ARRAY OF CHAR; c: HUGECARD);
  BEGIN
    Out.String(name); Out.String(" = "); Out.Card(c, 0); Out.String(" ");
    Out.CardHex(c, 1); Out.Ln
  END Show;

  PROCEDURE Sum(a: SHORTCARD; b: CARDINAL; c: LONGCARD; d: HUGECARD): HUGECARD;
  BEGIN
    RETURN a + b + c + d
  END Sum;

  PROCEDURE Double(VAR c: CARDINAL);
  BEGIN
    c := c * 2
  END Double;

  PROCEDURE Label(c: CARDINAL);
  BEGIN
    CASE c OF
      0: Out.String("zero")
    | 1..9: Out.String("few")
    | MAX(CARDINAL): Out.String("max")
    ELSE Out.String("other")
    END;
    Out.Ln
  END Label;

BEGIN
  Out.Int(SIZE(SHORTCARD), 2); Out.Int(SIZE(CARDINAL), 2); Out.Int(SIZE(LONGCARD), 2);
  Out.Int(SIZE(HUGECARD), 2); Out.Int(SIZE(Small), 3); Out.Ln;

  Show("MAX(SHORTCARD)", MAX(SHORTCARD)); Show("MAX(CARDINAL)", MAX(CARDINAL));
  Show("MAX(LONGCARD)", MAX(LONGCARD)); Show("MAX(HUGECARD)", MAX(HUGECARD));
  Show("MIN(CARDINAL)", MIN(CARDINAL));

  (* wrapping *)
  sc := MAX(SHORTCARD); INC(sc); Show("SHORTCARD MAX + 1", sc);
  sc := 0; DEC(sc); Show("SHORTCARD 0 - 1", sc);
  ca := MAX(CARDINAL); ca := ca + 1; Show("CARDINAL MAX + 1", ca);
  ca := 0; ca := ca - 1; Show("CARDINAL 0 - 1", ca);
  lc := MAX(LONGCARD); lc := lc * lc; Show("LONGCARD MAX * MAX", lc);
  hc := MAX(HUGECARD); hc := hc + 2; Show("HUGECARD MAX + 2", hc);
  ca := 1; ca := -ca; Show("-CARDINAL 1", ca);

  (* comparison, DIV and MOD are unsigned, at the top of each range *)
  sc := MAX(SHORTCARD); ca := MAX(CARDINAL); lc := MAX(LONGCARD); hc := MAX(HUGECARD);
  IF sc > 1 THEN Out.String("sc >") ELSE Out.String("sc <=") END;
  IF ca > 1 THEN Out.String(" ca >") ELSE Out.String(" ca <=") END;
  IF lc > 1 THEN Out.String(" lc >") ELSE Out.String(" lc <=") END;
  IF hc > 1 THEN Out.String(" hc >") ELSE Out.String(" hc <=") END;
  Out.Ln;
  Show("sc DIV 2", sc DIV 2); Show("sc MOD 7", sc MOD 7);
  Show("ca DIV 2", ca DIV 2); Show("ca MOD 7", ca MOD 7);
  Show("lc DIV 2", lc DIV 2); Show("lc MOD 7", lc MOD 7);
  Show("hc DIV 2", hc DIV 2); Show("hc MOD 7", hc MOD 7);

  (* shifts fill with zeros *)
  Show("ASH(sc, -1)", ASH(sc, -1)); Show("ASH(ca, -1)", ASH(ca, -1));
  Show("ASH(lc, -1)", ASH(lc, -1)); Show("ASH(hc, -1)", ASH(hc, -1));
  Show("ASH(ca, 1)", ASH(ca, 1));

  (* widening is by zeros, among themselves and into a real *)
  lc := ca; Show("LONGCARD := CARDINAL", lc);
  hc := MAX(LONGCARD); Show("HUGECARD := LONGCARD", hc);
  Show("LONG(sc)", LONG(sc)); Show("LONG(ca)", LONG(ca));
  Show("SHORT(hc)", SHORT(hc)); Show("SHORT(lc)", SHORT(lc)); Show("SHORT(ca)", SHORT(ca));
  r := MAX(CARDINAL); Out.LongReal(r, 16); Out.Ln;

  (* a constant widens its operand: under -O2 this is a LONGCARD *)
  ca := 65535; Show("ca + 70000", ca + 70000);

  (* FOR to MAX ends; a CARD steps down past 0 without wrapping *)
  n := 0; sc := 0;
  FOR sc := MAX(SHORTCARD) - 2 TO MAX(SHORTCARD) DO INC(n) END;
  Show("FOR to MAX left", sc); Out.Int(n, 0); Out.Ln;
  n := 0;
  FOR ca := 3 TO 0 BY -1 DO INC(n) END;
  Show("FOR down left", ca); Out.Int(n, 0); Out.Ln;

  (* CASE, an index, a parameter of each, by reference *)
  Label(0); Label(5); Label(MAX(CARDINAL)); Label(100);
  FOR i := 0 TO 7 DO arr[i] := i * i END;
  ca := 5; Out.Int(arr[ca], 0); Out.Ln;
  hc := 7; Out.Int(arr[hc], 0); Out.Ln;
  Show("Sum", Sum(255, 65535, 1, 1));
  ca := 21; Double(ca); Show("Double", ca);

  (* fields and elements, which layout places *)
  small.a := "a"; small.b := 200; small.c := 60000; small.d := 4000000000; small.e := MAX(HUGECARD);
  many[0] := 1; many[1] := 65535; many[2] := 3;
  Show("small.b", small.b); Show("small.c", small.c); Show("small.d", small.d);
  Show("small.e", small.e); Show("many[1]", many[1]);
  Out.Char(small.a); Out.Ln
END cardinal.
