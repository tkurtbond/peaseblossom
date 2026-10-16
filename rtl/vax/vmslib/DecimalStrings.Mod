MODULE DecimalStrings;

  (* Arithmetic on decimal numbers of up to 255 digits, by STR$'s decimal
     routines (doc/developer/vms-sdl-interfaces.md, part 9; VMS RTL String
     Manipulation (STR$) Manual). STR$ gives a number in three parts: a
     sign (0 positive, 1 negative), an exponent, and a string of unsigned
     digits, so that its value is the digits times 10 to the exponent with
     the sign applied. -999.9998 is sign 1, exponent -4, digits "9999998".
     A Decimal holds the three, its digits ended by 0X.

     Each arithmetic procedure returns STR$'s condition value: SS$_NORMAL;
     STR$_TRU (STRDEF) if the result has more than 255 digits; or a
     condition STR$ signals, such as STR$_DIVBY_ZER (which is severe, and
     would end the program) or LIB$_INVARG, returned and not signalled:
     the procedure establishes LIB$SIG_TO_RET as its handler, as Math's
     routines do in PocRtl.mar. So a signal from code an AST interrupted
     would find that handler too, and the module is not for AST routines.
     After any status but SS$_NORMAL the result is not a value: on
     STR$_TRU, STR$ keeps the first 255 digits with the exponent of all
     of them (vms-sdl-interfaces.md, "Part 9 done").

     STR$ writes a result's digits right-justified, with leading zeros,
     and moves its trailing zeros into the exponent (1000 is digits "1",
     exponent 3); a result's digits here have no leading zeros. Round's
     places are significant digits (123456.789 to 2 is 120000), and it
     rounds a half away from zero. Divide's digits are after the point.
     Reciprocal's result has one digit past the precision, truncated
     (1 / 7 to 0.000000000000001 is 0.1428571428571428). *)

  IMPORT SYSTEM, STR_ROUTINES, LIB_ROUTINES;

  CONST
    maxDigits* = 255;
    positive = 0; negative = 1; (* a sign *)

  TYPE
    Decimal* = RECORD
      sign*: SYSTEM.CARD32; (* 0 positive, 1 negative *)
      exponent*: SYSTEM.INT32; (* the power of 10 the digits are multiplied by *)
      digits*: ARRAY maxDigits + 1 OF CHAR (* unsigned, ended by 0X *)
    END;

    (* what STR$ writes a result's digits into: a CLASS_S descriptor of
       all of it *)
    Buffer = ARRAY maxDigits OF CHAR;

  (* d's digits from buffer, as STR$ left it: its digits without leading
     zeros or the blanks that fill it out, "0" if none *)
  PROCEDURE SetDigits(VAR d: Decimal; VAR buffer: Buffer);
    VAR i, n: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(buffer)) & ((buffer[i] = " ") OR (buffer[i] = "0")) DO INC(i) END;
    n := 0;
    WHILE (i < LEN(buffer)) & (buffer[i] >= "0") & (buffer[i] <= "9") DO
      d.digits[n] := buffer[i]; INC(n); INC(i)
    END;
    IF n = 0 THEN d.digits[0] := "0"; n := 1 END;
    d.digits[n] := 0X
  END SetDigits;

  (* d, 0 *)
  PROCEDURE Clear(VAR d: Decimal);
  BEGIN
    d.sign := positive; d.exponent := 0; d.digits := "0"
  END Clear;

  (* c, a + b *)
  PROCEDURE Add*(a, b: Decimal; VAR c: Decimal): SYSTEM.INT32;
    VAR handler: SYSTEM.ADDRESS; buffer: Buffer; status: SYSTEM.INT32;
  BEGIN
    handler := LIB_ROUTINES.LIB$ESTABLISH(SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$SIG_TO_RET));
    Clear(c);
    status := STR_ROUTINES.STR$ADD(a.sign, a.exponent, a.digits, b.sign, b.exponent, b.digits,
      c.sign, c.exponent, buffer);
    SetDigits(c, buffer);
    RETURN status
  END Add;

  (* c, a - b *)
  PROCEDURE Subtract*(a, b: Decimal; VAR c: Decimal): SYSTEM.INT32;
  BEGIN
    b.sign := 1 - b.sign;
    RETURN Add(a, b, c)
  END Subtract;

  (* c, a * b *)
  PROCEDURE Multiply*(a, b: Decimal; VAR c: Decimal): SYSTEM.INT32;
    VAR handler: SYSTEM.ADDRESS; buffer: Buffer; status: SYSTEM.INT32;
  BEGIN
    handler := LIB_ROUTINES.LIB$ESTABLISH(SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$SIG_TO_RET));
    Clear(c);
    status := STR_ROUTINES.STR$MUL(a.sign, a.exponent, a.digits, b.sign, b.exponent, b.digits,
      c.sign, c.exponent, buffer);
    SetDigits(c, buffer);
    RETURN status
  END Multiply;

  (* c, a / b to digits digits after the point, rounded or truncated
     (STR$DIVIDE, whose indicator is 1 to round) *)
  PROCEDURE Divide*(a, b: Decimal; digits: LONGINT; round: BOOLEAN; VAR c: Decimal): SYSTEM.INT32;
    VAR handler: SYSTEM.ADDRESS; buffer: Buffer; status: SYSTEM.INT32; indicator: SYSTEM.CARD32;
  BEGIN
    handler := LIB_ROUTINES.LIB$ESTABLISH(SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$SIG_TO_RET));
    Clear(c);
    IF round THEN indicator := 1 ELSE indicator := 0 END;
    status := STR_ROUTINES.STR$DIVIDE(a.sign, a.exponent, a.digits, b.sign, b.exponent, b.digits,
      SYSTEM.VAL(SYSTEM.INT32, digits), indicator, c.sign, c.exponent, buffer);
    SetDigits(c, buffer);
    RETURN status
  END Divide;

  (* c, 1 / a to the precision precision gives (STR$RECIP) *)
  PROCEDURE Reciprocal*(a, precision: Decimal; VAR c: Decimal): SYSTEM.INT32;
    VAR handler: SYSTEM.ADDRESS; buffer: Buffer; status: SYSTEM.INT32;
  BEGIN
    handler := LIB_ROUTINES.LIB$ESTABLISH(SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$SIG_TO_RET));
    Clear(c);
    status := STR_ROUTINES.STR$RECIP(a.sign, a.exponent, a.digits,
      precision.sign, precision.exponent, precision.digits, c.sign, c.exponent, buffer);
    SetDigits(c, buffer);
    RETURN status
  END Reciprocal;

  (* c, a rounded or truncated to places digits (STR$ROUND, whose flag is
     1 to truncate) *)
  PROCEDURE Round*(a: Decimal; places: LONGINT; truncate: BOOLEAN; VAR c: Decimal): SYSTEM.INT32;
    VAR handler: SYSTEM.ADDRESS; buffer: Buffer; status: SYSTEM.INT32; flags: SYSTEM.CARD32;
  BEGIN
    handler := LIB_ROUTINES.LIB$ESTABLISH(SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$SIG_TO_RET));
    Clear(c);
    IF truncate THEN flags := 1 ELSE flags := 0 END;
    status := STR_ROUTINES.STR$ROUND(SYSTEM.VAL(SYSTEM.INT32, places), flags,
      a.sign, a.exponent, a.digits, c.sign, c.exponent, buffer);
    SetDigits(c, buffer);
    RETURN status
  END Round;

  (* d from text: an optional sign, digits, and an optional point with
     digits after it, with at least one digit and at most maxDigits;
     whether text is one *)
  PROCEDURE FromText*(text: ARRAY OF CHAR; VAR d: Decimal): BOOLEAN;
    VAR i, n, after: INTEGER; point, ok: BOOLEAN;
  BEGIN
    Clear(d);
    i := 0; n := 0; after := 0; point := FALSE; ok := TRUE;
    IF text[0] = "-" THEN d.sign := negative; i := 1
    ELSIF text[0] = "+" THEN i := 1
    END;
    WHILE ok & (i < LEN(text)) & (text[i] # 0X) DO
      IF (text[i] >= "0") & (text[i] <= "9") THEN
        IF n < maxDigits THEN d.digits[n] := text[i]; INC(n) ELSE ok := FALSE END;
        IF point THEN INC(after) END
      ELSIF (text[i] = ".") & ~point THEN point := TRUE
      ELSE ok := FALSE
      END;
      INC(i)
    END;
    IF ok & (n > 0) THEN
      d.digits[n] := 0X; d.exponent := -after
    ELSE
      Clear(d); ok := FALSE
    END;
    RETURN ok
  END FromText;

  (* d, n *)
  PROCEDURE FromInteger*(n: HUGEINT; VAR d: Decimal);
    VAR magnitude: SYSTEM.CARD64; reversed: ARRAY 20 OF CHAR; k, i: INTEGER;
  BEGIN
    Clear(d);
    magnitude := SYSTEM.VAL(SYSTEM.CARD64, n);
    IF n < 0 THEN d.sign := negative; magnitude := -magnitude END;
    k := 0;
    REPEAT
      reversed[k] := CHR(ORD("0") + SYSTEM.VAL(SYSTEM.INT16, SHORT(SHORT(magnitude MOD 10))));
      magnitude := magnitude DIV 10; INC(k)
    UNTIL magnitude = 0;
    FOR i := 0 TO k - 1 DO d.digits[i] := reversed[k - 1 - i] END;
    d.digits[k] := 0X
  END FromInteger;

  (* text, d in plain form: "-999.9998", "2000", "0.0002"; cut to fit
     LEN(text) - 1 characters *)
  PROCEDURE ToText*(d: Decimal; VAR text: ARRAY OF CHAR);
    VAR n, i, k: INTEGER; length, places, zeros: LONGINT;

    PROCEDURE Put(c: CHAR);
    BEGIN
      IF k < LEN(text) - 1 THEN text[k] := c; INC(k) END
    END Put;

  BEGIN
    k := 0;
    n := 0;
    WHILE d.digits[n] # 0X DO INC(n) END;
    i := 0;
    WHILE (i < n - 1) & (d.digits[i] = "0") DO INC(i) END; (* leading zeros *)
    IF (d.sign = negative) & ~((n - i = 1) & (d.digits[i] = "0")) THEN Put("-") END;
    length := n - i;
    IF d.exponent >= 0 THEN
      WHILE i < n DO Put(d.digits[i]); INC(i) END;
      IF ~((length = 1) & (d.digits[n - 1] = "0")) THEN
        zeros := d.exponent;
        WHILE zeros > 0 DO Put("0"); DEC(zeros) END
      END
    ELSE
      places := -d.exponent;
      IF length > places THEN
        WHILE length > places DO Put(d.digits[i]); INC(i); DEC(length) END
      ELSE
        Put("0")
      END;
      Put(".");
      zeros := places - length;
      WHILE zeros > 0 DO Put("0"); DEC(zeros) END;
      WHILE i < n DO Put(d.digits[i]); INC(i) END
    END;
    text[k] := 0X
  END ToText;

END DecimalStrings.
