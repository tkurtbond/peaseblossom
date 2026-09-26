MODULE FormattedOutput;

  (* Phase 11 A26: the formatting behind Out (standard output) and Err
     (standard error), written once, with the descriptor to write to as
     every procedure's first parameter. Internal, like RealDigits: a program
     imports Out or Err. What each procedure prints, and how that differs
     from voc's Out, is described in Out.Mod; Int is Console.Int's.

     Nothing is buffered: every call has written its output when it returns,
     so Out, Err, Console and the trap messages come out in the order of the
     calls, and nothing is lost when a program ends without a Ln or is
     stopped by a trap. The writing itself is FileDescriptorOutput's (Phase
     11 D11), so that voc compiles this module too, over its own version of
     that one (rtl/voc), for Stage 0's Err. *)

  IMPORT SYSTEM, FileDescriptorOutput, RealDigits;

  CONST
    newline = 0AX;
    spaceChunk = 32; (* how many blanks Spaces writes at a time *)

  PROCEDURE Char*(descriptor: SYSTEM.INT32; ch: CHAR);
    VAR one: ARRAY 1 OF CHAR;
  BEGIN
    one[0] := ch;
    FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(one), 1)
  END Char;

  (* The characters of s up to its 0X (all of it if it has none), without
     the 0X, in one write. *)
  PROCEDURE String*(descriptor: SYSTEM.INT32; s: ARRAY OF CHAR);
    VAR length: LONGINT;
  BEGIN
    length := 0;
    WHILE (length < LEN(s)) & (s[length] # 0X) DO INC(length) END;
    IF length > 0 THEN FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(s), SYSTEM.VAL(SYSTEM.ADDRESS, length)) END
  END String;

  PROCEDURE Ln*(descriptor: SYSTEM.INT32);
  BEGIN
    Char(descriptor, newline)
  END Ln;

  PROCEDURE Spaces(descriptor: SYSTEM.INT32; count: HUGEINT);
    VAR blanks: ARRAY spaceChunk OF CHAR; k: LONGINT;
  BEGIN
    FOR k := 0 TO spaceChunk - 1 DO blanks[k] := " " END;
    WHILE count > spaceChunk DO
      FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(blanks), spaceChunk);
      DEC(count, spaceChunk)
    END;
    IF count > 0 THEN FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(blanks), SYSTEM.VAL(SYSTEM.ADDRESS, count)) END
  END Spaces;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. The smallest HUGEINT has no positive counterpart to print
     digit by digit, so it is written out whole. A negative n is
     taken as 0. *)
  PROCEDURE Int*(descriptor: SYSTEM.INT32; x, n: HUGEINT);
    VAR text: ARRAY 24 OF CHAR; first, length: LONGINT; magnitude: HUGEINT;
  BEGIN
    IF n < 0 THEN n := 0 END;
    IF x = MIN(HUGEINT) THEN
      Spaces(descriptor, n - 20);
      String(descriptor, "-9223372036854775808")
    ELSE
      IF x < 0 THEN magnitude := -x ELSE magnitude := x END;
      (* the digits, least significant first, at the end of text *)
      first := LEN(text);
      REPEAT
        DEC(first);
        text[first] := CHR(ORD("0") + magnitude MOD 10);
        magnitude := magnitude DIV 10
      UNTIL magnitude = 0;
      IF x < 0 THEN DEC(first); text[first] := "-" END;
      length := LEN(text) - first;
      Spaces(descriptor, n - length);
      FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(text) + SYSTEM.VAL(SYSTEM.ADDRESS, first),
               SYSTEM.VAL(SYSTEM.ADDRESS, length))
    END
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(descriptor: SYSTEM.INT32; x, n: HUGEINT);
    VAR text: ARRAY 17 OF CHAR; k: LONGINT; digit: HUGEINT; count: LONGINT;
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
    text[count] := 0X;
    String(descriptor, text)
  END Hex;

  (* Real and LongReal *)

  PROCEDURE digit(n: HUGEINT; VAR s: ARRAY OF CHAR; VAR i: INTEGER);
  BEGIN
    DEC(i);
    s[i] := CHR(n MOD 10 + 48)
  END digit;

  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR l: LONGINT;
  BEGIN
    l := 0;
    WHILE (l < LEN(s)) & (s[l] # 0X) DO INC(l) END;
    RETURN l
  END Length;

  (* t at the end of s, ending before position i; i moves to its start *)
  PROCEDURE prepend(t: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; VAR i: INTEGER);
    VAR j: INTEGER; l: LONGINT;
  BEGIN
    l := Length(t);
    IF l > i THEN l := i END;
    DEC(i, SHORT(l));
    j := 0;
    WHILE j < l DO s[i + j] := t[j]; INC(j) END
  END prepend;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;
    VAR r, power: LONGREAL;
  BEGIN
    r := 1.0D0;
    power := 1.0D1;
    WHILE e > 0 DO
      IF ODD(e) THEN r := r * power END;
      power := power * power;
      e := e DIV 2
    END;
    RETURN r
  END Ten;

  (* x in exponential form - d.dddE+dd, or d.dddD+ddd for a long one -
     right-aligned in a field of n characters, with as many digits as fit
     (at most 9, or 17 if long, and at least 2); voc's algorithm *)
  PROCEDURE RealP(descriptor: SYSTEM.INT32; x: LONGREAL; n: INTEGER; long: BOOLEAN);
    VAR
      e: INTEGER; (* exponent field *)
      f: HUGEINT; (* fraction field *)
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
      pad, k: LONGINT;
      text: ARRAY 32 OF CHAR; (* what is written: the sign, then s from i *)
  BEGIN
    e := SYSTEM.VAL(INTEGER, (SYSTEM.VAL(HUGEINT, x) DIV 10000000000000H) MOD 800H);
    f := SYSTEM.VAL(HUGEINT, x) MOD 10000000000000H;
    nn := (SYSTEM.VAL(HUGEINT, x) < 0) & ~((e = 7FFH) & (f # 0)); (* no sign on a NaN *)
    IF nn THEN DEC(n) END;

    i := SHORT(LEN(s));
    IF e = 7FFH THEN (* NaN, infinity *)
      IF f = 0 THEN prepend("Infinity", s, i) ELSE prepend("NaN", s, i) END
    ELSE
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

      IF (e = 0) & (f = 0) THEN
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
      digit(m, s, i)
    END;

    pad := n - (LEN(s) - i);
    k := 0;
    IF nn THEN text[0] := "-"; k := 1 END;
    WHILE i < LEN(s) DO text[k] := s[i]; INC(k); INC(i) END;
    text[k] := 0X;
    Spaces(descriptor, pad);
    String(descriptor, text)
  END RealP;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(descriptor: SYSTEM.INT32; x: REAL; n: INTEGER);
  BEGIN
    RealP(descriptor, x, n, FALSE)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(descriptor: SYSTEM.INT32; x: LONGREAL; n: INTEGER);
  BEGIN
    RealP(descriptor, x, n, TRUE)
  END LongReal;

END FormattedOutput.
