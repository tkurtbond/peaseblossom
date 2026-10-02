MODULE Reals;

  (* Phase 12 step 5f: voc's Reals interface - powers of ten, the binary
     exponent of a REAL or LONGREAL, and the digits Texts writes a real
     number from - written for poc.

     Where it differs from voc's:
     - Ten and TenL are correctly rounded, the C library's strtof/strtod of
       "1E<e>". voc's TenL multiplies powers of ten by repeated squaring
       and is off in the last bit for 252 of the 309 exponents 0..308 (its
       Ten, computed in LONGREAL, is exact). A negative e gives 10^e; voc's
       Ten answers 1 and its TenL something that is not a power of ten.
     - Expo, SetExpo, ExpoL, SetExpoL and ConvertH/ConvertHL take the
       number's bits as an integer, so they do not depend on the byte
       order, where voc's read bytes at offsets set from
       Platform.LittleEndian; the answers are the same.
     - ConvertL writes the low n digits of x's integer part exactly,
       however large x is. voc's converts x to a LONGINT, whose range ends
       near 9.2E18 under -OC and 2.1E18 (in two pieces) under -O2.

     As voc's, ConvertH and ConvertHL write the bytes least significant
     first, each as two hexadecimal digits, the high one first: the order
     of the bytes in memory on a little-endian machine (Ofront's, which
     wrote them in memory order), which voc keeps on a big-endian one. *)

  IMPORT SYSTEM;

  CONST
    realExponentUnit = 800000H;             (* 2^23, REAL's lowest exponent bit *)
    longRealExponentUnit = 10000000000000H; (* 2^52, LONGREAL's *)
    minLongRealExponent = -1074;            (* of a LONGREAL's lowest bit *)

  PROCEDURE ["C", "strtod"] CStrToD(text, end: SYSTEM.ADDRESS): LONGREAL;
  PROCEDURE ["C", "strtof"] CStrToF(text, end: SYSTEM.ADDRESS): REAL;

  (* text := "1E<e>", followed by 0X *)
  PROCEDURE PowerText(e: INTEGER; VAR text: ARRAY OF CHAR);
    VAR magnitude: HUGEINT; reversed: ARRAY 12 OF CHAR; count, i: INTEGER;
  BEGIN
    text[0] := "1"; text[1] := "E"; i := 2;
    magnitude := e;
    IF magnitude < 0 THEN text[i] := "-"; INC(i); magnitude := -magnitude END;
    count := 0;
    REPEAT
      reversed[count] := CHR(SYSTEM.VAL(INTEGER, magnitude MOD 10) + 48);
      magnitude := magnitude DIV 10; INC(count)
    UNTIL magnitude = 0;
    WHILE count > 0 DO DEC(count); text[i] := reversed[count]; INC(i) END;
    text[i] := 0X
  END PowerText;

  (* 10^e, correctly rounded; 0 or infinity beyond REAL's range *)
  PROCEDURE Ten*(e: INTEGER): REAL;
    VAR text: ARRAY 16 OF CHAR;
  BEGIN
    PowerText(e, text);
    RETURN CStrToF(SYSTEM.ADR(text), 0)
  END Ten;

  (* 10^e, correctly rounded; 0 or infinity beyond LONGREAL's range *)
  PROCEDURE TenL*(e: INTEGER): LONGREAL;
    VAR text: ARRAY 16 OF CHAR;
  BEGIN
    PowerText(e, text);
    RETURN CStrToD(SYSTEM.ADR(text), 0)
  END TenL;

  (* The biased exponent field of x: 0 for zero and the subnormals, 255
     for the infinities and NaNs *)
  PROCEDURE Expo*(x: REAL): INTEGER;
    VAR bits: HUGEINT;
  BEGIN
    bits := SYSTEM.VAL(SYSTEM.INT32, x);
    RETURN SYSTEM.VAL(INTEGER, bits DIV realExponentUnit MOD 256)
  END Expo;

  (* x's biased exponent field := ex MOD 256 *)
  PROCEDURE SetExpo*(VAR x: REAL; ex: INTEGER);
    VAR bits: HUGEINT; word: SYSTEM.INT32;
  BEGIN
    bits := SYSTEM.VAL(SYSTEM.INT32, x);
    bits := bits - bits DIV realExponentUnit MOD 256 * realExponentUnit
                 + ex MOD 256 * realExponentUnit;
    word := SYSTEM.VAL(SYSTEM.INT32, bits);
    x := SYSTEM.VAL(REAL, word)
  END SetExpo;

  (* The biased exponent field of x: 0 for zero and the subnormals, 2047
     for the infinities and NaNs *)
  PROCEDURE ExpoL*(x: LONGREAL): INTEGER;
    VAR bits: HUGEINT;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, x);
    RETURN SYSTEM.VAL(INTEGER, bits DIV longRealExponentUnit MOD 2048)
  END ExpoL;

  (* x's biased exponent field := ex MOD 2048 *)
  PROCEDURE SetExpoL*(VAR x: LONGREAL; ex: INTEGER);
    VAR bits: HUGEINT;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, x);
    bits := bits - bits DIV longRealExponentUnit MOD 2048 * longRealExponentUnit
                 + ex MOD 2048 * longRealExponentUnit;
    x := SYSTEM.VAL(LONGREAL, bits)
  END SetExpoL;

  (* d[0 .. n-1] := the low n decimal digits of the integer part of |x|,
     least significant first, "0"s past its first digit. Texts calls it with
     x scaled to the n digits it wants. x = m * 2^e exactly (m < 2^53, from
     x's bits), so for e < 0 the integer part is m DIV 2^-e, and for e >= 0
     its low n digits are m's, doubled e times, each time keeping n digits.
     An infinity or NaN gives the digits of its bits read as a number. *)
  PROCEDURE ConvertL*(x: LONGREAL; n: INTEGER; VAR d: ARRAY OF CHAR);
    VAR
      bits, mantissa: HUGEINT; biased, e, k, digit, carry: INTEGER;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, x);
    biased := SYSTEM.VAL(INTEGER, bits DIV longRealExponentUnit MOD 2048);
    mantissa := bits MOD longRealExponentUnit;
    IF biased = 0 THEN
      e := minLongRealExponent
    ELSE
      mantissa := mantissa + longRealExponentUnit; e := biased - 1075
    END;
    IF e < 0 THEN
      IF e <= -53 THEN mantissa := 0 ELSE mantissa := ASH(mantissa, e) END;
      e := 0
    END;
    k := 0;
    WHILE k < n DO
      d[k] := CHR(SYSTEM.VAL(INTEGER, mantissa MOD 10) + 48);
      mantissa := mantissa DIV 10; INC(k)
    END;
    WHILE e > 0 DO
      carry := 0; k := 0;
      WHILE k < n DO
        digit := (ORD(d[k]) - 48) * 2 + carry;
        d[k] := CHR(digit MOD 10 + 48); carry := digit DIV 10; INC(k)
      END;
      DEC(e)
    END
  END ConvertL;

  (* ConvertL of x *)
  PROCEDURE Convert*(x: REAL; n: INTEGER; VAR d: ARRAY OF CHAR);
  BEGIN
    ConvertL(x, n, d)
  END Convert;

  PROCEDURE HexDigit(value: INTEGER): CHAR;
  BEGIN
    IF value < 10 THEN RETURN CHR(value + 48) ELSE RETURN CHR(value + 55) END
  END HexDigit;

  (* d[0 .. 2*byteCount-1] := the low byteCount bytes of bits, least
     significant first, two hexadecimal digits each, the high one first *)
  PROCEDURE BytesToHex(bits: HUGEINT; byteCount: INTEGER; VAR d: ARRAY OF CHAR);
    VAR k, byte: INTEGER;
  BEGIN
    k := 0;
    WHILE k < byteCount DO
      byte := SYSTEM.VAL(INTEGER, bits MOD 256);
      d[2 * k] := HexDigit(byte DIV 16); d[2 * k + 1] := HexDigit(byte MOD 16);
      bits := bits DIV 256; INC(k)
    END
  END BytesToHex;

  (* d[0 .. 7] := y's 4 bytes in hexadecimal (BytesToHex) *)
  PROCEDURE ConvertH*(y: REAL; VAR d: ARRAY OF CHAR);
    VAR bits: HUGEINT;
  BEGIN
    bits := SYSTEM.VAL(SYSTEM.INT32, y);
    BytesToHex(bits, 4, d)
  END ConvertH;

  (* d[0 .. 15] := x's 8 bytes in hexadecimal (BytesToHex) *)
  PROCEDURE ConvertHL*(x: LONGREAL; VAR d: ARRAY OF CHAR);
  BEGIN
    BytesToHex(SYSTEM.VAL(HUGEINT, x), 8, d)
  END ConvertHL;

END Reals.
