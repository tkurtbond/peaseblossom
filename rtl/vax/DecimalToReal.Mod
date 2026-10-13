MODULE DecimalToReal;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.7, proposal 4): the F_floating or G_floating value nearest a decimal
     numeral, ties to even - what Reals.Ten and TenL give, and later
     Strings, In, InStr and FormattedInput, where rtl/llvm's call C's strtof
     and strtod (doc/research/vms-module-inventory.md, proposal 3).
     Internal, like RealDigits: a program imports one of those.

     The method is src/front/DecimalToDouble.Mod's, the compiler's own, with
     HUGEINT where that has its 8-byte LONGINT, which the runtime cannot
     assume under -O2, and the VAX's formats for IEEE 754's: no floating-
     point arithmetic decides any digit. The numeral is a big integer D and
     a decimal exponent a, its value V = D * 10^a; the answer is the integer
     m, 2^(p-1) <= m < 2^p for p bits of precision, and binary exponent e
     with m * 2^e nearest to V. Dividing is avoided by cross-multiplying:
     with V = D * 5^a * 2^a, "q <= V / 2^e" is "left >= q * factor" for two
     big integers built from D, 5^|a| and a power of two, so the q nearest
     below V / 2^e is found by binary search over q (58 comparisons), and the
     remainder is compared with one half by "2 * left" against "(2q + 1) *
     factor", giving the rounding, ties to even. e comes from the digit
     count (a lower bound of it, so q starts a few bits too long), then is
     raised by exactly what q's own length says.

     Ties go to even, as IEEE 754 rounds and as RealDigits does, not away
     from zero, as the VAX's arithmetic and MACRO round (section 14, item
     9): a numeral exactly halfway between two values can differ in its
     last bit from the same numeral written as a constant in a program.

     The VAX has no subnormals: below the smallest value, 2^-1024 for G and
     2^-128 for F, the result is the nearer of 0 and the smallest, the
     smallest when exactly halfway. The last step, m * 2^e, is exact: m fits
     a LONGREAL, a power of two scales without rounding, and the result is
     representable by construction; a REAL is that LONGREAL shortened,
     exactly.

     Digits past maxDigits do not need to be looked at one by one: only
     whether any of them is nonzero matters, which is recorded by appending
     one further digit 1 (the numeral's value is then just above what the
     kept digits say, on the same side of every midpoint). *)

  CONST
    limbBase = 32768;
    maxLimbs = 400; (* 6000 bits: the largest number here is under 3800 *)
    maxDigits = 800;
    quotientBits = 58; (* q is always below 2^58 *)
    (* G_floating's precision, the binary exponent of its smallest value's
       last bit, and of its largest value's; and F_floating's *)
    longPrecision = 53; longLowest = -1076; longHighest = 970;
    shortPrecision = 24; shortLowest = -151; shortHighest = 103;

  TYPE
    (* limb[0] is the least significant; n limbs are in use (0 for zero) *)
    Big = RECORD
      n: LONGINT;
      limb: ARRAY maxLimbs OF HUGEINT
    END;

  PROCEDURE Trim(VAR a: Big);
  BEGIN
    WHILE (a.n > 0) & (a.limb[a.n - 1] = 0) DO DEC(a.n) END
  END Trim;

  (* a := a * m + c, for 0 <= m < limbBase and 0 <= c < limbBase *)
  PROCEDURE MulAdd(VAR a: Big; m, c: HUGEINT);
    VAR i: LONGINT; carry, t: HUGEINT;
  BEGIN
    carry := c; i := 0;
    WHILE i < a.n DO
      t := a.limb[i] * m + carry;
      a.limb[i] := t MOD limbBase;
      carry := t DIV limbBase;
      INC(i)
    END;
    IF carry > 0 THEN a.limb[a.n] := carry; INC(a.n) END
  END MulAdd;

  PROCEDURE ShiftLeft(VAR a: Big; bits: LONGINT);
    VAR factor: HUGEINT;
  BEGIN
    WHILE bits >= 14 DO MulAdd(a, 16384, 0); DEC(bits, 14) END;
    IF bits > 0 THEN
      factor := 1;
      WHILE bits > 0 DO factor := factor * 2; DEC(bits) END;
      MulAdd(a, factor, 0)
    END
  END ShiftLeft;

  (* a := a * 5^k, six powers at a time (5^6 = 15625 < limbBase) *)
  PROCEDURE MulPower5(VAR a: Big; k: LONGINT);
    VAR factor: HUGEINT;
  BEGIN
    WHILE k >= 6 DO MulAdd(a, 15625, 0); DEC(k, 6) END;
    IF k > 0 THEN
      factor := 1;
      WHILE k > 0 DO factor := factor * 5; DEC(k) END;
      MulAdd(a, factor, 0)
    END
  END MulPower5;

  (* -1, 0 or 1 as a is less than, equal to or greater than b *)
  PROCEDURE Compare(VAR a, b: Big): INTEGER;
    VAR i: LONGINT;
  BEGIN
    IF a.n # b.n THEN
      IF a.n < b.n THEN RETURN -1 ELSE RETURN 1 END
    END;
    i := a.n - 1;
    WHILE i >= 0 DO
      IF a.limb[i] # b.limb[i] THEN
        IF a.limb[i] < b.limb[i] THEN RETURN -1 ELSE RETURN 1 END
      END;
      DEC(i)
    END;
    RETURN 0
  END Compare;

  (* r := f * q, for 0 <= q < 2^60 (four limbs) *)
  PROCEDURE MulLong(VAR f: Big; q: HUGEINT; VAR r: Big);
    VAR i, j: LONGINT; qj, carry, t: HUGEINT;
  BEGIN
    FOR i := 0 TO f.n + 4 DO r.limb[i] := 0 END;
    j := 0;
    WHILE q > 0 DO
      qj := q MOD limbBase; q := q DIV limbBase;
      carry := 0;
      FOR i := 0 TO f.n - 1 DO
        t := r.limb[i + j] + f.limb[i] * qj + carry;
        r.limb[i + j] := t MOD limbBase;
        carry := t DIV limbBase
      END;
      i := f.n + j;
      WHILE carry > 0 DO
        t := r.limb[i] + carry;
        r.limb[i] := t MOD limbBase;
        carry := t DIV limbBase;
        INC(i)
      END;
      INC(j)
    END;
    r.n := f.n + 5;
    Trim(r)
  END MulLong;

  PROCEDURE Copy(VAR from, to: Big);
    VAR i: LONGINT;
  BEGIN
    to.n := from.n;
    FOR i := 0 TO from.n - 1 DO to.limb[i] := from.limb[i] END
  END Copy;

  (* The left and right sides of V / 2^e compared with an integer q:
     V / 2^e >= q exactly when left >= q * factor. V = digits * 10^a, and
     10^a is 5^a * 2^a; the powers of two and five go to whichever side keeps
     every exponent non-negative. *)
  PROCEDURE Scale(VAR digits: Big; a, e: LONGINT; VAR left, factor: Big);
    VAR p: LONGINT;
  BEGIN
    Copy(digits, left);
    factor.n := 1; factor.limb[0] := 1;
    IF a >= 0 THEN MulPower5(left, a) ELSE MulPower5(factor, -a) END;
    p := a - e;
    IF p >= 0 THEN ShiftLeft(left, p) ELSE ShiftLeft(factor, -p) END
  END Scale;

  (* The largest q, 0 <= q < 2^quotientBits, with q * factor <= left. *)
  PROCEDURE Quotient(VAR left, factor, product: Big): HUGEINT;
    VAR low, high, mid: HUGEINT; i: INTEGER;
  BEGIN
    low := 0; high := 1;
    FOR i := 1 TO quotientBits DO high := high * 2 END;
    WHILE high - low > 1 DO
      mid := (low + high) DIV 2;
      MulLong(factor, mid, product);
      IF Compare(product, left) <= 0 THEN low := mid ELSE high := mid END
    END;
    RETURN low
  END Quotient;

  (* The bit length of q > 0: the least b with q < 2^b. *)
  PROCEDURE BitLength(q: HUGEINT): LONGINT;
    VAR bits: LONGINT;
  BEGIN
    bits := 0;
    WHILE q > 0 DO q := q DIV 2; INC(bits) END;
    RETURN bits
  END BitLength;

  PROCEDURE PowerOfTwo(exponent: LONGINT): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    result := 1.0D0;
    WHILE exponent > 0 DO result := result * 2.0D0; DEC(exponent) END;
    RETURN result
  END PowerOfTwo;

  (* v * 2^e, exact whenever the result is representable: never a step of
     more than 2^1000, so no intermediate result is out of range unless the
     answer is. *)
  PROCEDURE ScaleByPowerOfTwo(v: LONGREAL; e: LONGINT): LONGREAL;
    VAR big: LONGREAL;
  BEGIN
    big := PowerOfTwo(1000);
    WHILE e > 1000 DO v := v * big; DEC(e, 1000) END;
    WHILE e < -1000 DO v := v / big; INC(e, 1000) END;
    IF e >= 0 THEN RETURN v * PowerOfTwo(e) ELSE RETURN v / PowerOfTwo(-e) END
  END ScaleByPowerOfTwo;

  (* The value of the numeral - digits with an optional point and fraction,
     then an optional "E" or "D" exponent with an optional sign, as Lexer.Mod
     reads a real numeral - rounded to precision bits, its last bit's binary
     exponent at least lowest, into value; FALSE, value the largest, (2^p -
     1) * 2^highest, when that exponent is beyond highest. *)
  PROCEDURE Rounded(VAR numeral: ARRAY OF CHAR; precision, lowest, highest: LONGINT;
                    VAR value: LONGREAL): BOOLEAN;
    VAR
      digits, left, factor, product, twice: Big;
      i, kept, exponent10, magnitude, e, bits, written: LONGINT;
      d, q, m, half: HUGEINT;
      inFraction, sticky, negativeExponent: BOOLEAN;
      cmp: INTEGER;
  BEGIN
    digits.n := 0; kept := 0; exponent10 := 0; sticky := FALSE;
    i := 0; inFraction := FALSE;
    WHILE (i < LEN(numeral))
        & (((numeral[i] >= "0") & (numeral[i] <= "9")) OR ((numeral[i] = ".") & ~inFraction)) DO
      IF numeral[i] = "." THEN
        inFraction := TRUE
      ELSE
        d := ORD(numeral[i]) - ORD("0");
        IF (digits.n > 0) OR (d # 0) THEN
          IF kept < maxDigits THEN
            MulAdd(digits, 10, d); INC(kept);
            IF inFraction THEN DEC(exponent10) END
          ELSE
            IF d # 0 THEN sticky := TRUE END;
            IF ~inFraction THEN INC(exponent10) END
          END
        ELSIF inFraction THEN
          DEC(exponent10) (* a zero before the first significant digit *)
        END
      END;
      INC(i)
    END;
    IF (i < LEN(numeral)) & ((numeral[i] = "E") OR (numeral[i] = "D")) THEN
      INC(i); negativeExponent := FALSE;
      IF (i < LEN(numeral)) & (numeral[i] = "-") THEN negativeExponent := TRUE; INC(i)
      ELSIF (i < LEN(numeral)) & (numeral[i] = "+") THEN INC(i)
      END;
      written := 0;
      WHILE (i < LEN(numeral)) & (numeral[i] >= "0") & (numeral[i] <= "9") DO
        IF written < 30000 THEN written := written * 10 + (ORD(numeral[i]) - ORD("0")) END;
        INC(i)
      END;
      IF negativeExponent THEN exponent10 := exponent10 - written ELSE exponent10 := exponent10 + written END
    END;
    IF digits.n = 0 THEN value := 0.0D0; RETURN TRUE END;
    IF sticky THEN MulAdd(digits, 10, 1); INC(kept); DEC(exponent10) END;
    (* the value is in [10^(magnitude - 1), 10^magnitude) *)
    magnitude := kept + exponent10;
    IF magnitude > 310 THEN
      value := ScaleByPowerOfTwo(PowerOfTwo(precision) - 1.0D0, highest); RETURN FALSE
    ELSIF magnitude < -330 THEN
      value := 0.0D0; RETURN TRUE
    END;

    (* a lower bound of the binary exponent e for which V / 2^e has
       precision bits, and one bit to spare for the estimate's own error *)
    e := ENTIER((magnitude - 1) * 3.321928094887362D0) - precision;
    IF e < lowest THEN e := lowest END;
    LOOP
      Scale(digits, exponent10, e, left, factor);
      q := Quotient(left, factor, product);
      bits := BitLength(q);
      IF bits > precision THEN
        e := e + (bits - precision)
      ELSIF (bits < precision) & (e > lowest) THEN
        e := e - (precision - bits);
        IF e < lowest THEN e := lowest END
      ELSE
        EXIT
      END
    END;
    IF bits < precision THEN
      (* below the smallest value, 2^(precision - 1) * 2^lowest: q * 2^lowest
         <= V, so V is at least half of it exactly when q is *)
      half := 1;
      FOR i := 1 TO precision - 2 DO half := half * 2 END;
      IF q >= half THEN m := 2 * half ELSE value := 0.0D0; RETURN TRUE END
    ELSE
      (* q * 2^e <= V < (q + 1) * 2^e, and q has precision bits: round to
         nearest, ties to even, by comparing 2 * left with (2q + 1) * factor *)
      Copy(left, twice); MulAdd(twice, 2, 0);
      MulLong(factor, 2 * q + 1, product);
      cmp := Compare(twice, product);
      IF (cmp > 0) OR ((cmp = 0) & ODD(q)) THEN m := q + 1 ELSE m := q END;
      IF BitLength(m) > precision THEN (* rounded up: exactly 2^(precision - 1) * 2^(e + 1) *)
        m := m DIV 2; INC(e)
      END
    END;
    IF e > highest THEN
      value := ScaleByPowerOfTwo(PowerOfTwo(precision) - 1.0D0, highest); RETURN FALSE
    END;
    value := ScaleByPowerOfTwo(m, e);
    RETURN TRUE
  END Rounded;

  (* The G_floating value nearest the numeral (as Rounded), up to its 0X or
     the end of the array, into value; FALSE, value the largest LONGREAL,
     when it is beyond that. *)
  PROCEDURE ToLongReal*(numeral: ARRAY OF CHAR; VAR value: LONGREAL): BOOLEAN;
  BEGIN
    RETURN Rounded(numeral, longPrecision, longLowest, longHighest, value)
  END ToLongReal;

  (* The F_floating value nearest the numeral, not the G_floating value
     nearest it shortened, which can differ; FALSE, value the largest REAL,
     when it is beyond that. *)
  PROCEDURE ToReal*(numeral: ARRAY OF CHAR; VAR value: REAL): BOOLEAN;
    VAR long: LONGREAL; inRange: BOOLEAN;
  BEGIN
    inRange := Rounded(numeral, shortPrecision, shortLowest, shortHighest, long);
    value := SHORT(long);
    RETURN inRange
  END ToReal;

END DecimalToReal.
