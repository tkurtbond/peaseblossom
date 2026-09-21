MODULE valueFns;
  (* Phase 11 step 2 (inventory A1): ORD, ABS, CHR, CAP, ENTIER, LONG, SHORT
     and ODD of constants are folded, in a CONST declaration and in an
     ordinary expression alike. Every value here is the same under -O2 and
     -OC; semantic-const-value-functions pins the types, which differ. *)
  IMPORT Out;

  CONST
    ordA = ORD("A");
    ordHigh = ORD(0FFX);
    chr66 = CHR(66);
    capQ = CAP("q");
    capDigit = CAP("7");
    capChr = CAP(chr66);
    absNeg = ABS(-500);
    absZero = ABS(0);
    absPos = ABS(42);
    entierUp = ENTIER(2.5);
    entierDown = ENTIER(-2.5D0);
    entierExact = ENTIER(-3.0);
    entierBig = ENTIER(1.0D9);
    long500 = LONG(500);
    oddThree = ODD(3);
    oddNegative = ODD(-3);
    oddFour = ODD(4);
    oddComputed = ODD(ORD("A"));
    nested = ORD(CAP(CHR(ORD("a") + 1)));   (* 66: "b" capitalized *)
    arraySize = ORD("D") - 60;               (* 8 *)

  VAR
    buffer: ARRAY arraySize OF CHAR;
    single, other: REAL;
    double: LONGREAL;
    small: SHORTINT;
    wide: LONGINT;

  PROCEDURE Line(name: ARRAY OF CHAR; value: HUGEINT);
  BEGIN
    Out.String(name); Out.String(" = "); Out.Int(value, 0); Out.Ln
  END Line;

  PROCEDURE Flag(name: ARRAY OF CHAR; value: BOOLEAN);
  BEGIN
    Out.String(name); Out.String(" = ");
    IF value THEN Out.String("TRUE") ELSE Out.String("FALSE") END;
    Out.Ln
  END Flag;

BEGIN
  Line("ORD(A)", ordA);
  Line("ORD(0FFX)", ordHigh);
  Out.String("CHR(66) = "); Out.Char(chr66); Out.Ln;
  Out.String("CAP(q) = "); Out.Char(capQ); Out.Ln;
  Out.String("CAP(7) = "); Out.Char(capDigit); Out.Ln;
  Out.String("CAP(CHR(66)) = "); Out.Char(capChr); Out.Ln;
  Line("ABS(-500)", absNeg);
  Line("ABS(0)", absZero);
  Line("ABS(42)", absPos);
  Line("ENTIER(2.5)", entierUp);
  Line("ENTIER(-2.5D0)", entierDown);
  Line("ENTIER(-3.0)", entierExact);
  Line("ENTIER(1.0D9)", entierBig);
  Line("LONG(500)", long500);
  Flag("ODD(3)", oddThree);
  Flag("ODD(-3)", oddNegative);
  Flag("ODD(4)", oddFour);
  Flag("ODD(ORD(A))", oddComputed);
  Line("nested", nested);
  Line("LEN(buffer)", LEN(buffer));

  (* in ordinary expressions, folded to a constant of the minimal type: no
     wrap where the operand's own type would be too narrow *)
  wide := ABS(-40000) + 1;             Line("ABS(-40000) + 1", wide);
  small := ABS(-100);                  Line("small := ABS(-100)", small);
  wide := ENTIER(1.0D9) * 2;           Line("ENTIER(1.0D9) * 2", wide);
  wide := LONG(500) * 1000;            Line("LONG(500) * 1000", wide);
  Line("ORD(A) + ORD(B)", ORD("A") + ORD("B"));

  (* a real: ABS keeps a literal's exact numeral, LONG and SHORT round
     through single precision *)
  single := ABS(-0.1); other := 0.1;
  Flag("ABS(-0.1) = 0.1", single = other);
  double := LONG(0.1); Flag("LONG(0.1) = LONG(0.1 REAL)", double = LONG(other));
  single := SHORT(0.1D0); Flag("SHORT(0.1D0) = 0.1", single = other);
  double := ABS(-2.5D0); Flag("ABS(-2.5D0) = 2.5D0", double = 2.5D0);
  Out.Flush
END valueFns.
