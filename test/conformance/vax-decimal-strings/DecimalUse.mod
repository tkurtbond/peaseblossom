MODULE DecimalUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 9): STR$'s
     decimal arithmetic through VMSLIB's DecimalStrings, and twice through
     STR_ROUTINES itself, to show how STR$ fills a fixed-length result:
     the manual's example (STR-6), and a result too long for its buffer.
     Each step prints its status by name and its result as text and as
     its three parts. *)
  IMPORT SYSTEM, Out, DecimalStrings, STR_ROUTINES, STRDEF, LIBDEF, SSDEF;

  VAR
    a, b, c, precision: DecimalStrings.Decimal;
    text: ARRAY 300 OF CHAR;
    sign: SYSTEM.CARD32; exponent: SYSTEM.INT32;
    wide: ARRAY 40 OF CHAR;
    narrow: ARRAY 5 OF CHAR;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = STRDEF.STR$_TRU THEN Out.String("STR$_TRU")
    ELSIF status = STRDEF.STR$_DIVBY_ZER THEN Out.String("STR$_DIVBY_ZER")
    ELSIF status = LIBDEF.LIB$_INVARG THEN Out.String("LIB$_INVARG")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* d as text, then its parts *)
  PROCEDURE Print(VAR d: DecimalStrings.Decimal);
  BEGIN
    DecimalStrings.ToText(d, text);
    Out.String("  "); Out.String(text);
    Out.String("  (sign "); Out.Card(d.sign, 0); Out.String(", exponent "); Out.Int(d.exponent, 0);
    Out.String(", digits "); Out.String(d.digits); Out.String(")"); Out.Ln
  END Print;

  (* d from s, which must be good *)
  PROCEDURE Set(VAR d: DecimalStrings.Decimal; s: ARRAY OF CHAR);
  BEGIN
    IF ~DecimalStrings.FromText(s, d) THEN Out.String("  bad text "); Out.String(s); Out.Ln END
  END Set;

  (* s, between bars, each character as it is *)
  PROCEDURE Raw(s: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    Out.String("  |");
    FOR i := 0 TO LEN(s) - 1 DO
      IF s[i] < " " THEN Out.Char("^"); Out.Char(CHR(ORD(s[i]) + 64)) ELSE Out.Char(s[i]) END
    END;
    Out.String("|"); Out.Ln
  END Raw;

  PROCEDURE Parse(s: ARRAY OF CHAR);
  BEGIN
    Out.String("  FromText("); Out.String(s); Out.String("): ");
    IF DecimalStrings.FromText(s, a) THEN Out.String("TRUE"); Out.Ln; Print(a)
    ELSE Out.String("FALSE"); Out.Ln
    END
  END Parse;

BEGIN
  Out.String("the manual's example, through STR$ADD itself, a 40-character result"); Out.Ln;
  Show("STR$ADD", STR_ROUTINES.STR$ADD(1, 3, "1", 0, -4, "2", sign, exponent, wide));
  Raw(wide);
  Out.String("  sign "); Out.Card(sign, 0); Out.String(", exponent "); Out.Int(exponent, 0); Out.Ln;

  Out.String("the same through DecimalStrings: -1000 + 0.0002"); Out.Ln;
  Set(a, "-1000"); Set(b, "0.0002");
  Show("Add", DecimalStrings.Add(a, b, c)); Print(c);
  Show("Subtract", DecimalStrings.Subtract(a, b, c)); Print(c);

  Out.String("beyond HUGEINT"); Out.Ln;
  Set(a, "123456789012345678901234567890"); Set(b, "987654321098765432109876543210");
  Show("Multiply", DecimalStrings.Multiply(a, b, c)); Print(c);
  Set(a, "0.5"); Set(b, "12.75");
  Show("Subtract 0.5 - 12.75", DecimalStrings.Subtract(a, b, c)); Print(c);
  DecimalStrings.FromInteger(MIN(HUGEINT), a); Print(a);
  DecimalStrings.FromInteger(-1, b);
  Show("Add MIN(HUGEINT) + -1", DecimalStrings.Add(a, b, c)); Print(c);

  Out.String("Divide"); Out.Ln;
  Set(a, "1"); Set(b, "3");
  Show("1 / 3, 20 digits, truncated", DecimalStrings.Divide(a, b, 20, FALSE, c)); Print(c);
  Set(a, "2");
  Show("2 / 3, 20 digits, truncated", DecimalStrings.Divide(a, b, 20, FALSE, c)); Print(c);
  Show("2 / 3, 20 digits, rounded", DecimalStrings.Divide(a, b, 20, TRUE, c)); Print(c);
  Set(a, "-22.5"); Set(b, "4");
  Show("-22.5 / 4, 3 digits, rounded", DecimalStrings.Divide(a, b, 3, TRUE, c)); Print(c);
  Set(b, "0");
  Show("2 / 0", DecimalStrings.Divide(a, b, 5, FALSE, c)); Print(c);

  Out.String("Reciprocal"); Out.Ln;
  Set(a, "7"); Set(precision, "0.000000000000001");
  Show("1 / 7, precision 1E-15", DecimalStrings.Reciprocal(a, precision, c)); Print(c);
  Set(a, "0");
  Show("1 / 0", DecimalStrings.Reciprocal(a, precision, c)); Print(c);

  Out.String("Round"); Out.Ln;
  Set(a, "3.14159265");
  Show("3.14159265, 4, rounded", DecimalStrings.Round(a, 4, FALSE, c)); Print(c);
  Show("3.14159265, 4, truncated", DecimalStrings.Round(a, 4, TRUE, c)); Print(c);
  Set(a, "-2.5");
  Show("-2.5, 1, rounded", DecimalStrings.Round(a, 1, FALSE, c)); Print(c);
  Set(a, "123456.789");
  Show("123456.789, 2, rounded", DecimalStrings.Round(a, 2, FALSE, c)); Print(c);

  Out.String("text"); Out.Ln;
  Parse("+12"); Parse(".5"); Parse("-0.000"); Parse("1.2.3"); Parse("12a"); Parse("-");
  a.sign := 0; a.exponent := 5; a.digits := "42"; Print(a);
  a.sign := 1; a.exponent := -8; a.digits := "42"; Print(a);

  Out.String("STR$MUL itself, a 5-character result"); Out.Ln;
  Show("STR$MUL", STR_ROUTINES.STR$MUL(0, 0, "12345", 0, 0, "6789", sign, exponent, narrow));
  Raw(narrow);
  Out.String("  sign "); Out.Card(sign, 0); Out.String(", exponent "); Out.Int(exponent, 0); Out.Ln
END DecimalUse.
