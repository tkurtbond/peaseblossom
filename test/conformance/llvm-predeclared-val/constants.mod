MODULE constants;
  (* VAL of a constant is a constant of type T, with no import *)
  IMPORT Out;
  CONST
    top = VAL(CARDINAL, 65535);
    fromTop = VAL(INTEGER, top - 65500);
    negative = VAL(SHORTINT, -5);
    huge = VAL(HUGECARD, 0FFFFFFFFFFFFFFFFH);
    half = VAL(HUGEINT, huge DIV 2);
    named = VAL(SHORTCARD, 200);
  VAR
    a: ARRAY VAL(INTEGER, named) OF CHAR;
    c: CARDINAL;
BEGIN
  Out.Card(top, 0); Out.Ln;
  Out.Int(fromTop, 0); Out.Ln;
  Out.Int(negative, 0); Out.Ln;
  Out.Card(huge, 0); Out.Ln;
  Out.Int(half, 0); Out.Ln;
  Out.Int(LEN(a), 0); Out.Ln;
  Out.Int(SIZE(CARDINAL), 0); Out.Ln;
  c := 65535;
  CASE c OF
    VAL(CARDINAL, 65535): Out.String("case"); Out.Ln
  ELSE Out.String("not case"); Out.Ln
  END;
  (* the constant keeps its type: SHORTCARD wraps *)
  Out.Card(named + named, 0); Out.Ln
END constants.
