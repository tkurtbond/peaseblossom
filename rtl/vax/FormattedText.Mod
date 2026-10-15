MODULE FormattedText;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.7, proposal 2): rtl/llvm/FormattedText.Mod for the VAX, the text of
     each number Out and Err write, without the blanks that pad it to its
     field. Internal, like RealDigits: a program imports Out or Err. What
     each procedure makes is described in rtl/llvm/Out.Mod.

     Two things differ from rtl/llvm's, both for the VAX's reals, F_floating
     and G_floating (section 14, item 9), which have no infinities, NaNs,
     subnormals or -0:
     - RealP tells zero and the sign by comparing (x = 0, x < 0), not by
       reading IEEE 754's bits, and has no Infinity or NaN. The reserved
       operand faults at the first comparison, as any use of it does.
     - Ten stops squaring once e is used up. rtl/llvm's squares once more,
       which for e >= 256 is past G_floating's range: an infinity thrown
       away there, a floating-overflow fault here. So Ten(256) to Ten(307)
       work; past 307 the product itself overflows.

     Int, Real and LongReal are right-aligned in a field of n characters:
     the caller pads with n - Length(text) blanks, nothing if that is not
     positive. Hex has no field, only a digit count. *)

  IMPORT SYSTEM, RealDigits;

  CONST
    (* the room every text below needs, its 0X included *)
    maxText* = 32;

  (* The characters of text before its first 0X (all of it if it has
     none) *)
  PROCEDURE Length*(VAR text: ARRAY OF CHAR): LONGINT;
    VAR l: LONGINT;
  BEGIN
    l := 0;
    WHILE (l < LEN(text)) & (text[l] # 0X) DO INC(l) END;
    RETURN l
  END Length;

  (* x in decimal, with a minus sign if it is negative, and no plus sign.
     The smallest HUGEINT has no positive counterpart to make digit by
     digit, so it is written out whole. *)
  PROCEDURE Int*(x: HUGEINT; VAR text: ARRAY OF CHAR);
    VAR digits: ARRAY 24 OF CHAR; first, k: LONGINT; magnitude: HUGEINT;
  BEGIN
    IF x = MIN(HUGEINT) THEN
      COPY("-9223372036854775808", text)
    ELSE
      IF x < 0 THEN magnitude := -x ELSE magnitude := x END;
      (* the digits, least significant first, at the end of digits *)
      first := LEN(digits) - 1; digits[first] := 0X;
      REPEAT
        DEC(first);
        digits[first] := CHR(ORD("0") + magnitude MOD 10);
        magnitude := magnitude DIV 10
      UNTIL magnitude = 0;
      IF x < 0 THEN DEC(first); digits[first] := "-" END;
      k := 0;
      WHILE digits[first + k] # 0X DO text[k] := digits[first + k]; INC(k) END;
      text[k] := 0X
    END
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT; VAR text: ARRAY OF CHAR);
    VAR k: LONGINT; digit: HUGEINT; count: LONGINT;
  BEGIN
    IF n < 1 THEN n := 1 ELSIF n > 16 THEN n := 16 END;
    count := SYSTEM.VAL(LONGINT, n);
    IF x >= 0 THEN
      WHILE (count < 16) & (ASH(x, -4 * count) # 0) DO INC(count) END
    END;
    FOR k := 0 TO count - 1 DO
      digit := ASH(x, -4 * (count - 1 - k)) MOD 16;
      IF digit <= 9 THEN text[k] := CHR(ORD("0") + digit)
      ELSE text[k] := CHR(ORD("A") - 10 + digit)
      END
    END;
    text[count] := 0X
  END Hex;

  (* x's 64 bits read as an unsigned integer (a SYSTEM.CARD64's, taken as
     a HUGEINT so that voc can compile this module), in decimal: x itself
     if it is not negative, else x + 2^64. For a negative x, that is 2h + b
     with b its low bit and h = ASH(x, -1) + 2^63 (the arithmetic shift,
     moved up by 2^63, is the logical one), and h = 5q + s, so the value
     is 10q + 2s + b: q's digits, then 2s + b. *)
  PROCEDURE Card*(x: HUGEINT; VAR text: ARRAY OF CHAR);
    VAR half, last: HUGEINT; l: LONGINT;
  BEGIN
    IF x >= 0 THEN
      Int(x, text)
    ELSE
      half := ASH(x, -1) - MIN(HUGEINT);
      Int(half DIV 5, text);
      last := 2 * (half MOD 5);
      IF ODD(x) THEN INC(last) END;
      l := Length(text);
      text[l] := CHR(ORD("0") + last); text[l + 1] := 0X
    END
  END Card;

  (* x's 64 bits read as an unsigned integer, as Card, in hexadecimal
     digits, upper case: at least n of them (n is taken to be within
     1..16), and as many as the value needs if that is more. *)
  PROCEDURE CardHex*(x, n: HUGEINT; VAR text: ARRAY OF CHAR);
  BEGIN
    IF x < 0 THEN Hex(x, 16, text) ELSE Hex(x, n, text) END
  END CardHex;

  (* Real and LongReal *)

  PROCEDURE digit(n: HUGEINT; VAR s: ARRAY OF CHAR; VAR i: INTEGER);
  BEGIN
    DEC(i);
    s[i] := CHR(n MOD 10 + 48)
  END digit;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22; up to
     10^307, past which G_floating overflows *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;
    VAR r, power: LONGREAL;
  BEGIN
    r := 1.0D0;
    power := 1.0D1;
    WHILE e > 0 DO
      IF ODD(e) THEN r := r * power END;
      e := e DIV 2;
      IF e > 0 THEN power := power * power END
    END;
    RETURN r
  END Ten;

  (* x in exponential form - d.dddE+dd, or d.dddD+ddd for a long one - with
     as many digits as fit a field of n characters (at most 9, or 17 if
     long, and at least 2); voc's algorithm *)
  PROCEDURE RealP(x: LONGREAL; n: INTEGER; long: BOOLEAN; VAR text: ARRAY OF CHAR);
    VAR
      s: ARRAY 30 OF CHAR; (* buffer built backwards *)
      i: INTEGER; (* index into s *)
      el: INTEGER; (* exponent length *)
      e10: INTEGER; (* decimal exponent *)
      digitText: ARRAY 20 OF CHAR; (* the digits, RealDigits' *)
      nn: BOOLEAN; (* number negative *)
      en: BOOLEAN; (* exponent negative *)
      m: HUGEINT; (* mantissa digits *)
      d: INTEGER; (* significant digit count to display *)
      dr: INTEGER; (* number of insignificant digits that can be dropped *)
      k: LONGINT;
  BEGIN
    nn := x < 0.0D0;
    IF nn THEN DEC(n) END;

    i := SHORT(LEN(s));
    (* how many significant digits the caller has room for, and how many
       to generate *)
    IF long THEN
      el := 3;
      dr := n - 6; (* room for the point and "+D000" *)
      IF dr > 17 THEN dr := 17 END; (* the most that are useful *)
      d := dr;
      IF d < 15 THEN d := 15 END (* enough to tell trailing zeros *)
    ELSE
      el := 2;
      dr := n - 5; (* room for the point and "+E00" *)
      IF dr > 9 THEN dr := 9 END;
      d := dr;
      IF d < 6 THEN d := 6 END
    END;

    IF x = 0.0D0 THEN
      WHILE el > 0 DO DEC(i); s[i] := "0"; DEC(el) END;
      DEC(i); s[i] := "+";
      m := 0
    ELSE
      IF nn THEN x := -x END;
      RealDigits.Digits(x, d, digitText, e10);
      m := 0; k := 0;
      WHILE k < d DO m := m * 10 + (ORD(digitText[k]) - 48); INC(k) END;

      (* the exponent's digits *)
      en := e10 < 0;
      IF en THEN e10 := -e10 END;
      WHILE el > 0 DO digit(e10, s, i); e10 := e10 DIV 10; DEC(el) END;
      DEC(i);
      IF en THEN s[i] := "-" ELSE s[i] := "+" END
    END;

    DEC(i);
    IF long THEN s[i] := "D" ELSE s[i] := "E" END;

    (* drop trailing zeros where the caller asked for less room *)
    IF dr < 2 THEN dr := 2 END;
    WHILE (d > dr) & (m MOD 10 = 0) DO m := m DIV 10; DEC(d) END;

    (* the digits *)
    WHILE d > 1 DO digit(m, s, i); m := m DIV 10; DEC(d) END;
    DEC(i);
    s[i] := ".";
    digit(m, s, i);

    k := 0;
    IF nn THEN text[0] := "-"; k := 1 END;
    WHILE i < LEN(s) DO text[k] := s[i]; INC(k); INC(i) END;
    text[k] := 0X
  END RealP;

  (* x in exponential form (d.dddE+dd), with as many digits as fit a field
     of n characters, from 2 to 9, at least 6 generated to drop trailing
     zeros from. A plus sign of the mantissa is not written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER; VAR text: ARRAY OF CHAR);
  BEGIN
    RealP(x, n, FALSE, text)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER; VAR text: ARRAY OF CHAR);
  BEGIN
    RealP(x, n, TRUE, text)
  END LongReal;

END FormattedText.
