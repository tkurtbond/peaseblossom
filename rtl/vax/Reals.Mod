MODULE Reals;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.7, proposal 5): rtl/llvm/Reals.Mod for the VAX - powers of ten, the
     binary exponent of a REAL or LONGREAL, and the digits Texts writes a
     real number from - for its reals, F_floating and G_floating (section
     14, item 9), which have no infinities, NaNs, subnormals or -0.

     An F_floating value is two 16-bit words, the more significant first in
     memory: in the first, the sign is bit 15, the exponent bits 14:7
     (excess 128) and the fraction's top seven bits 6:0, the second word
     the rest of its 23 bits. G_floating is four words, the exponent bits
     14:4 (excess 1024) and 52 bits of fraction. The value is 0.1f *
     2^(exponent - bias); exponent 0 is zero, or the reserved operand when
     the sign is 1, which faults when it is used.

     Where it differs from rtl/llvm's:
     - Ten and TenL are DecimalToReal's value of "1E<e>", correctly
       rounded, ties to even, where rtl/llvm's are the C library's. Beyond
       the range they give the largest value of the type, as Files reads an
       IEEE infinity: Ten(39) and TenL(309) are those. Below it they give
       the nearer of 0 and the smallest value, so TenL(-309) is 0, and
       Ten(-38) is a full-precision number.
     - Expo, SetExpo, ExpoL and SetExpoL read and write the VAX's own
       exponent field, 8 bits excess 128 or 11 bits excess 1024: Expo(1.0)
       is 129, where IEEE's is 127. SetExpo and SetExpoL write only the
       field, so SetExpo(x, 0) of a negative x makes the reserved operand,
       as writing that field by hand would, which faults when it is used;
       and the VAX takes a positive value with exponent 0 as an exact zero
       wherever it is used as a real (MACRO and Instruction Set 5.4,
       "Floating-point 0").
     - ConvertL takes x apart as G_floating; a zero or the reserved operand
       writes zeros.
     - ConvertH and ConvertHL are rtl/llvm's: the bytes in memory order,
       least significant address first, which here are F's and G's, so
       ConvertH(1.0) is "80400000", where IEEE's is "0000803F".

     As rtl/llvm's (the numbers are those of vishap-bugs): a negative e gives
     10^e in Ten and TenL (D20), and ConvertL writes the low n digits of x's
     integer part exactly, however large x is (D18). *)

  IMPORT SYSTEM, DecimalToReal;

  CONST
    wordBase = 10000H;          (* 2^16 *)
    longMantissaTop = 10000000000000H; (* 2^52, a G_floating's hidden bit *)

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

  (* 10^e, correctly rounded; beyond REAL's range the largest REAL, below
     it the nearer of 0 and the smallest *)
  PROCEDURE Ten*(e: INTEGER): REAL;
    VAR text: ARRAY 16 OF CHAR; value: REAL; inRange: BOOLEAN;
  BEGIN
    PowerText(e, text);
    (* beyond the range, value is the largest REAL, as wanted *)
    inRange := DecimalToReal.ToReal(text, value);
    RETURN value
  END Ten;

  (* 10^e, correctly rounded; beyond LONGREAL's range the largest LONGREAL,
     below it the nearer of 0 and the smallest *)
  PROCEDURE TenL*(e: INTEGER): LONGREAL;
    VAR text: ARRAY 16 OF CHAR; value: LONGREAL; inRange: BOOLEAN;
  BEGIN
    PowerText(e, text);
    (* beyond the range, value is the largest LONGREAL, as wanted *)
    inRange := DecimalToReal.ToLongReal(text, value);
    RETURN value
  END TenL;

  (* The exponent field of x's first word, the low word of bits, below its
     fraction's top bits (fractionBits of them) and above its sign *)
  PROCEDURE FirstWordExponent(bits: HUGEINT; fractionBits: INTEGER; mask: HUGEINT): INTEGER;
    VAR first: HUGEINT;
  BEGIN
    first := bits MOD wordBase;
    RETURN SYSTEM.VAL(INTEGER, ASH(first, -fractionBits) MOD mask)
  END FirstWordExponent;

  (* bits with that field := ex MOD mask *)
  PROCEDURE SetFirstWordExponent(bits: HUGEINT; fractionBits: INTEGER; mask: HUGEINT; ex: INTEGER): HUGEINT;
    VAR unit: HUGEINT;
  BEGIN
    unit := ASH(1, fractionBits);
    RETURN bits - FirstWordExponent(bits, fractionBits, mask) * unit + ex MOD mask * unit
  END SetFirstWordExponent;

  (* The exponent field of x, excess 128: 0 for zero and the reserved
     operand *)
  PROCEDURE Expo*(x: REAL): INTEGER;
  BEGIN
    RETURN FirstWordExponent(SYSTEM.VAL(SYSTEM.INT32, x), 7, 256)
  END Expo;

  (* x's exponent field := ex MOD 256. x is read and written as an
     integer (SYSTEM.GET and PUT, MOVL), not as a REAL, so that only the
     field changes: a floating move would make a positive x with exponent 0
     a true zero, and fault on the reserved operand. *)
  PROCEDURE SetExpo*(VAR x: REAL; ex: INTEGER);
    VAR bits: HUGEINT; word: SYSTEM.INT32;
  BEGIN
    SYSTEM.GET(SYSTEM.ADR(x), word);
    bits := SetFirstWordExponent(word, 7, 256, ex);
    word := SYSTEM.VAL(SYSTEM.INT32, bits);
    SYSTEM.PUT(SYSTEM.ADR(x), word)
  END SetExpo;

  (* The exponent field of x, excess 1024: 0 for zero and the reserved
     operand *)
  PROCEDURE ExpoL*(x: LONGREAL): INTEGER;
  BEGIN
    RETURN FirstWordExponent(SYSTEM.VAL(HUGEINT, x), 4, 2048)
  END ExpoL;

  (* x's exponent field := ex MOD 2048, read and written as an integer, as
     SetExpo does *)
  PROCEDURE SetExpoL*(VAR x: LONGREAL; ex: INTEGER);
    VAR bits: HUGEINT;
  BEGIN
    SYSTEM.GET(SYSTEM.ADR(x), bits);
    SYSTEM.PUT(SYSTEM.ADR(x), SetFirstWordExponent(bits, 4, 2048, ex))
  END SetExpoL;

  (* d[0 .. n-1] := the low n decimal digits of the integer part of |x|,
     least significant first, "0"s past its first digit. Texts calls it with
     x scaled to the n digits it wants. x = m * 2^e exactly (m < 2^53, from
     x's four words, as RealDigits takes them), so for e < 0 the integer
     part is m DIV 2^-e, and for e >= 0 its low n digits are m's, doubled e
     times, each time keeping n digits. A zero or the reserved operand
     gives zeros. *)
  PROCEDURE ConvertL*(x: LONGREAL; n: INTEGER; VAR d: ARRAY OF CHAR);
    VAR
      bits, mantissa: HUGEINT; biased, e, k, digit, carry: INTEGER;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, x);
    biased := FirstWordExponent(bits, 4, 2048);
    mantissa := bits MOD wordBase MOD 16;
    FOR k := 1 TO 3 DO
      bits := bits DIV wordBase;
      mantissa := mantissa * wordBase + bits MOD wordBase
    END;
    IF biased = 0 THEN
      mantissa := 0; e := 0
    ELSE
      mantissa := mantissa + longMantissaTop; e := biased - 1077
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
