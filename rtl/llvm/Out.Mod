MODULE Out;

  (* PLAN.md Phase 10 step 5: the Oakwood Guidelines' Out module, formatted
     output to the standard output stream, with voc's interface (src/
     runtime/Out.Mod): Open, Flush, Char, String, Int, Hex, Ln, Real,
     LongReal, and voc's Ten and IsConsole. It is the module poc's own
     Diagnostics.Mod prints through (Char, String, Int, Ln).

     Like Console.Mod, which it writes through, it is unbuffered: every call
     has written its output when it returns, so Out and Console (and the
     trap messages) interleave in the order of the calls, and nothing is
     lost when a program ends without a Ln. Flush and Open therefore do
     nothing. voc buffers 128 characters and flushes at each line end.

     Where this differs from voc's:
     - Int has no wrong answer for the smallest HUGEINT (voc's prints a
       fixed, wrong string), and Hex needs no SYSTEM.LSH/ROT;
     - Real and LongReal are voc's algorithm, step for step, so they print
       what voc's do, and so, for the same reasons, they are *not always
       correctly rounded*: the decimal exponent is estimated as 77/256 of
       the binary one and the number is scaled by a power of ten computed
       in floating point (Ten), which is exact only up to 10^22, so the
       last digits of a number outside about 10^-22..10^22 - or the last
       of the 17 a LONGREAL can be asked for - may be off by a few units.
       A correctly rounded conversion (and a correctly rounded reading of
       text, which In gets from the C library) is Phase 11 work; the same
       one is missing from ConstantEvaluator.ParseReal. *)

  IMPORT SYSTEM, Console;

  CONST
    spaceChunk = 32;

  VAR
    IsConsole-: BOOLEAN;

  PROCEDURE ["C", "isatty"] CIsATerminal(descriptor: SYSTEM.INT32): SYSTEM.INT32;

  (* Initializes the output stream; there is nothing to do. *)
  PROCEDURE Open*;
  BEGIN
  END Open;

  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    Console.Char(ch)
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  BEGIN
    Console.String(str)
  END String;

  PROCEDURE Ln*;
  BEGIN
    Console.Ln
  END Ln;

  PROCEDURE Spaces(count: HUGEINT);
  BEGIN
    WHILE count > spaceChunk DO
      Console.String("                                ");
      DEC(count, spaceChunk)
    END;
    WHILE count > 0 DO Console.Char(" "); DEC(count) END
  END Spaces;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x, n: HUGEINT);
  BEGIN
    IF n > MAX(LONGINT) THEN n := MAX(LONGINT) ELSIF n < 0 THEN n := 0 END;
    Console.Int(x, SYSTEM.VAL(LONGINT, n))
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT);
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
    Console.String(text)
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

  (* The whole number part of x, for 0 <= x < 2^63, cut from the bits of x
     (ENTIER gives a LONGINT, too narrow for the 17 digits wanted here) *)
  PROCEDURE WholePart(x: LONGREAL): HUGEINT;
    VAR bits, fraction: HUGEINT; e: INTEGER;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, x);
    e := SYSTEM.VAL(INTEGER, (bits DIV 10000000000000H) MOD 800H);
    fraction := bits MOD 10000000000000H;
    IF e = 0 THEN RETURN 0 END; (* zero, or a denormal: below 1 *)
    e := e - 1075; (* x = (2^52 + fraction) * 2^e *)
    IF e > 10 THEN RETURN MAX(HUGEINT) END;
    IF e < -63 THEN RETURN 0 END;
    RETURN ASH(10000000000000H + fraction, e)
  END WholePart;

  (* x in exponential form - d.dddE+dd, or d.dddD+ddd for a long one -
     right-aligned in a field of n characters, with as many digits as fit
     (at most 9, or 17 if long, and at least 2); voc's algorithm *)
  PROCEDURE RealP(x: LONGREAL; n: INTEGER; long: BOOLEAN);
    VAR
      e: INTEGER; (* exponent field *)
      f: HUGEINT; (* fraction field *)
      s: ARRAY 30 OF CHAR; (* buffer built backwards *)
      i: INTEGER; (* index into s *)
      el: INTEGER; (* exponent length *)
      x0: LONGREAL;
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

      IF e = 0 THEN
        WHILE el > 0 DO DEC(i); s[i] := "0"; DEC(el) END;
        DEC(i); s[i] := "+";
        m := 0
      ELSE
        IF nn THEN x := -x END;

        (* e as a power of ten, not of two *)
        e := SHORT(LONG(e - 1023) * 77 DIV 256);
        IF e >= 0 THEN x := x / Ten(e) ELSE x := Ten(-e) * x END;
        IF x >= 10.0D0 THEN x := 0.1D0 * x; INC(e) END;

        (* the exponent's digits *)
        en := e < 0;
        IF en THEN e := -e END;
        WHILE el > 0 DO digit(e, s, i); e := e DIV 10; DEC(el) END;
        DEC(i);
        IF en THEN s[i] := "-" ELSE s[i] := "+" END;

        (* x scaled to enough digits to tell trailing zeros, or as many as
           there is room for *)
        x0 := Ten(d - 1);
        x := x0 * x;
        x := x + 0.5D0; (* not folded into the line above: doing so changes the
                           last bit between 32- and 64-bit builds (voc's note) *)
        IF x >= 10.0D0 * x0 THEN x := 0.1D0 * x; INC(e) END;
        m := WholePart(x)
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
    Spaces(pad);
    Console.String(text)
  END RealP;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER);
  BEGIN
    RealP(x, n, FALSE)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
  BEGIN
    RealP(x, n, TRUE)
  END LongReal;

BEGIN
  IsConsole := CIsATerminal(1) # 0
END Out.
