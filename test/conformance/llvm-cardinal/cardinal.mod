MODULE cardinal;
  (* The unsigned types SYSTEM.CARD8..CARD64 and SYSTEM.CARD (AGENTS.md,
     "Unsigned integer types"): arithmetic modulo 2^n, unsigned comparison,
     DIV and MOD, zero extension, ASH and LSH shifting in zeros, indexing,
     CASE, FOR counting down, SYSTEM.VAL across the families, constants
     above MAX(HUGEINT) as hexadecimal patterns, and the text procedures
     Out.Card/CardHex, Err's, OutStr's and InStr.Card. Nothing printed
     depends on SYSTEM.CARD's width. *)
  IMPORT S := SYSTEM, Out, Err, OutStr, InStr;

  CONST
    top = 0FFFFFFFFFFFFFFFFH; (* 2^64 - 1 for a CARD64 *)
    half = 08000000000000000H; (* 2^63 *)
    maxWord = S.VAL(S.CARD32, 4294967295);

  TYPE
    Pair = RECORD low: S.CARD8; high: S.CARD16 END;

  VAR
    a, b: S.CARD8; w: S.CARD16; d, e: S.CARD32; q, r: S.CARD64; c: S.CARD;
    n: LONGINT; i: INTEGER; x: LONGREAL; set: SET; ch: CHAR;
    table: ARRAY 256 OF INTEGER; pair: Pair;
    text: ARRAY 64 OF CHAR; pos: LONGINT;

  PROCEDURE Flag(x: BOOLEAN);
  BEGIN
    IF x THEN Out.String("T") ELSE Out.String("F") END
  END Flag;

  PROCEDURE Show(label: ARRAY OF CHAR; v: S.CARD64);
  BEGIN
    Out.String(label); Out.Char(" "); Out.Card(v, 0); Out.Ln
  END Show;

  PROCEDURE Halve(v: S.CARD32): S.CARD32;
  BEGIN
    RETURN v DIV 2
  END Halve;

  PROCEDURE Bump(VAR v: S.CARD16);
  BEGIN
    INC(v, 40000)
  END Bump;

BEGIN
  (* wrapping, at each width *)
  a := 200; b := 100; Show("200+100 CARD8", a + b);
  a := 0; DEC(a); Show("0-1 CARD8", a);
  w := 65535; INC(w); Show("65535+1 CARD16", w);
  d := maxWord; Show("max CARD32", d); e := d + 1; Show("+1", e);
  q := top; Show("max CARD64", q); INC(q); Show("+1", q);
  a := 16; a := a * 16; Show("16*16 CARD8", a);
  a := 3; a := -a; Show("-3 CARD8", a);
  (* comparison, DIV and MOD are unsigned *)
  a := 200; b := 100;
  Flag(a > b); Flag(a > 150); Flag(a >= 200); Flag(b < a); Flag(a = 200); Flag(a # b);
  q := top; Flag(q > 1); Flag(q > half); r := half; Flag(r > 0); Out.Ln;
  Show("200 DIV 7", a DIV 7); Show("200 MOD 7", a MOD 7);
  q := top; Show("max64 DIV 3", q DIV 3); Show("max64 MOD 10", q MOD 10);
  d := maxWord; Show("max32 DIV 2", Halve(d));
  (* widening is zero extension, into reals too *)
  a := 255; w := a; d := w; q := d; Show("255 widened", q);
  w := LONG(a); d := LONG(w); q := LONG(d); Show("LONG", q);
  w := 300; a := SHORT(w); Show("SHORT(300)", a);
  x := a; Out.LongReal(x, 12); Out.Ln;
  q := top; x := q; Out.LongReal(x, 12); Out.Ln;
  x := a * 1.5; Out.LongReal(x, 12); Out.Ln;
  (* constants of a CARD's type *)
  a := 255; w := a + 300; Show("255+300", w);
  q := S.VAL(S.CARD64, 0) - 1; Show("folded 0-1", q);
  Show("MAX(CARD8)", MAX(S.CARD8)); Show("MAX(CARD16)", MAX(S.CARD16));
  Show("MAX(CARD32)", MAX(S.CARD32)); Show("MAX(CARD64)", MAX(S.CARD64));
  Show("MIN(CARD64)", MIN(S.CARD64));
  q := half; Show("2^63", q);
  (* SYSTEM.VAL across the families *)
  a := 200; Out.Int(S.VAL(INTEGER, LONG(a)), 0); Out.Char(" ");
  i := -1; d := S.VAL(S.CARD32, i); Out.Card(d, 0); Out.Char(" ");
  n := -2; q := S.VAL(S.CARD64, n); Out.CardHex(q, 1); Out.Char(" ");
  q := top; Out.Int(S.VAL(HUGEINT, q), 0); Out.Ln;
  c := S.VAL(S.CARD, -1); Flag(c = MAX(S.CARD)); c := 0; DEC(c); Flag(c = MAX(S.CARD));
  c := 5; q := c; Flag(q = 5); Out.Ln;
  d := 0F0F0F0F0H; set := S.VAL(SET, d); Flag(4 IN set); Flag(3 IN set); Out.Ln;
  (* shifts *)
  a := 128; Show("ASH(128,-1)", ASH(a, -1)); Show("ASH(128,1)", ASH(a, 1));
  q := half; Show("ASH(2^63,-63)", ASH(q, -63));
  a := 129; Show("LSH(129,-1)", S.LSH(a, -1)); Show("ROT(129,1)", S.ROT(a, 1));
  (* indexing, records, CASE, ODD, ABS, CHR, IN *)
  a := 200; table[a] := 7; Out.Int(table[200], 0); Out.Ln;
  pair.low := 255; pair.high := pair.low; INC(pair.high); Show("pair.high", pair.high);
  FOR i := 0 TO 2 DO
    CASE i OF 0: a := 5 | 1: a := 130 | 2: a := 255 END;
    CASE a OF 0..127: Out.String("low ") | 128..254: Out.String("high ") | 255: Out.String("max ") END
  END;
  Out.Ln;
  a := 255; Flag(ODD(a)); Out.Char(" "); Show("ABS", ABS(a)); ch := CHR(a); Out.Int(ORD(ch), 0); Out.Ln;
  a := 3; set := {}; INCL(set, a); Flag(a IN set); Out.Ln;
  w := 30000; Bump(w); Show("Bump", w);
  (* FOR counts down to 0 and up to MAX, and ends *)
  n := 0; FOR a := 5 TO 0 BY -1 DO INC(n) END; Out.Int(n, 0); Out.Char(" "); Out.Card(a, 0); Out.Ln;
  n := 0; FOR a := 250 TO 255 DO INC(n) END; Out.Int(n, 0); Out.Char(" "); Out.Card(a, 0); Out.Ln;
  n := 0; FOR a := 0 TO 255 BY 100 DO INC(n) END; Out.Int(n, 0); Out.Char(" "); Out.Card(a, 0); Out.Ln;
  n := 0; FOR q := MAX(S.CARD64) - 2 TO top DO INC(n) END; Out.Int(n, 0); Out.Ln;
  (* the text procedures *)
  q := top; Out.Card(q, 24); Out.Char("|"); Out.CardHex(q, 1); Out.Char("|"); Out.CardHex(a, 4); Out.Ln;
  q := MAX(S.CARD64) - 1; Err.Card(q, 0); Err.Char(" "); Err.CardHex(q, 2); Err.Ln;
  text := ""; a := 255; OutStr.Card(a, 5, text); OutStr.CardHex(a, 4, text); OutStr.Card(top, 0, text);
  Out.String(text); Out.Ln;
  text := " 18446744073709551615 0FFH 7 -3"; pos := 0;
  REPEAT
    InStr.Card(q, text, pos);
    IF InStr.Done THEN Out.Card(q, 0); Out.Char(" ") ELSE Out.String("not done ") END
  UNTIL ~InStr.Done;
  Out.Int(pos, 0); Out.Ln
END cardinal.
