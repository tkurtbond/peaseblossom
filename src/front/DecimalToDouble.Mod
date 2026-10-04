MODULE DecimalToDouble;

  (* Phase 11 step 2 (inventory A2): the correctly rounded value of a
     decimal numeral - the LONGREAL nearest to it, ties to even - which
     ConstantEvaluator.ParseReal used to only approximate (digit
     accumulation and repeated scaling by ten: right to within a few units
     in the last place, wrong exactly where it mattered, a value near a
     midpoint or of extreme magnitude).

     The method is the exact one: no floating-point arithmetic decides any
     digit. The numeral is a big integer D and a decimal exponent a, its
     value D * 10^a; the answer is the integer m, 2^52 <= m < 2^53 (fewer
     bits below the smallest normal number), and binary exponent e with m *
     2^e nearest to it. Dividing is avoided by cross-multiplying: with V =
     D * 10^a = D * 5^a * 2^a, "q <= V / 2^e" is "L >= q * F" for two big
     integers L and F built from D, 5^|a| and a power of two, so the q
     nearest below V/2^e is found by binary search over q (58 comparisons),
     and the remainder is compared with one half by "2 * L" against "(2q+1)
     * F", giving the rounding, ties to even. e itself comes from the
     digit count (a lower bound of it, so q starts a few bits too long),
     then is raised by exactly what q's own length says. Nothing but
     integer multiplication, addition and comparison on 15-bit limbs is
     used, so the result cannot depend on the host's floating-point width
     (x87's extended precision, say); the last step, m * 2^e, is exact
     (m fits a LONGREAL, a power of two scales without rounding, and the
     result is representable by construction).

     Digits past maxDigits do not need to be looked at one by one: only
     whether any of them is nonzero matters, which is recorded by appending
     one further digit 1 (the numeral's value is then just above what the
     kept digits say, on the same side of every midpoint). A numeral whose
     magnitude is beyond 10^310 is infinity (a product that overflows, as
     the old routine's repeated multiplication gave) and one below 10^-330
     is 0.

     Requires a LONGINT of 8 bytes (poc is built with voc's -OC), for q and
     m; every other quantity is at most 31 bits. Written in plain
     Oberon2.pdf Oberon-2, like the rest of poc. *)

  CONST
    limbBits = 15;
    limbBase = 32768;
    maxLimbs = 400; (* 6000 bits: the largest number here is under 3800 *)
    maxDigits = 800;
    minExponent = -1074; (* the binary exponent of the smallest subnormal's last bit *)
    quotientBits = 58; (* q is always below 2^58 *)

  TYPE
    (* limb[0] is the least significant; n limbs are in use (0 for zero) *)
    Big = RECORD
      n: INTEGER;
      limb: ARRAY maxLimbs OF LONGINT
    END;

  PROCEDURE Trim(VAR a: Big);
  BEGIN
    WHILE (a.n > 0) & (a.limb[a.n - 1] = 0) DO DEC(a.n) END
  END Trim;

  (* a := a * m + c, for 0 <= m < limbBase and 0 <= c < limbBase *)
  PROCEDURE MulAdd(VAR a: Big; m, c: LONGINT);
    VAR i: INTEGER; carry, t: LONGINT;
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

  PROCEDURE ShiftLeft(VAR a: Big; bits: INTEGER);
    VAR factor: LONGINT;
  BEGIN
    WHILE bits >= 14 DO MulAdd(a, 16384, 0); DEC(bits, 14) END;
    IF bits > 0 THEN
      factor := 1;
      WHILE bits > 0 DO factor := factor * 2; DEC(bits) END;
      MulAdd(a, factor, 0)
    END
  END ShiftLeft;

  (* a := a * 5^k, six powers at a time (5^6 = 15625 < limbBase) *)
  PROCEDURE MulPower5(VAR a: Big; k: INTEGER);
    VAR factor: LONGINT;
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
    VAR i: INTEGER;
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
  PROCEDURE MulLong(VAR f: Big; q: LONGINT; VAR r: Big);
    VAR i, j: INTEGER; qj, carry, t: LONGINT;
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
    VAR i: INTEGER;
  BEGIN
    to.n := from.n;
    FOR i := 0 TO from.n - 1 DO to.limb[i] := from.limb[i] END
  END Copy;

  (* The left and right sides of V / 2^e compared with an integer q:
     V / 2^e >= q exactly when left >= q * factor. V = digits * 10^a, and
     10^a is 5^a * 2^a; the powers of two and five go to whichever side keeps
     every exponent non-negative. *)
  PROCEDURE Scale(VAR digits: Big; a, e: INTEGER; VAR left, factor: Big);
    VAR p: INTEGER;
  BEGIN
    Copy(digits, left);
    factor.n := 1; factor.limb[0] := 1;
    IF a >= 0 THEN MulPower5(left, a) ELSE MulPower5(factor, -a) END;
    p := a - e;
    IF p >= 0 THEN ShiftLeft(left, p) ELSE ShiftLeft(factor, -p) END
  END Scale;

  (* The largest q, 0 <= q < 2^quotientBits, with q * factor <= left. *)
  PROCEDURE Quotient(VAR left, factor, product: Big): LONGINT;
    VAR low, high, mid: LONGINT; i: INTEGER;
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
  PROCEDURE BitLength(q: LONGINT): INTEGER;
    VAR bits: INTEGER;
  BEGIN
    bits := 0;
    WHILE q > 0 DO q := q DIV 2; INC(bits) END;
    RETURN bits
  END BitLength;

  PROCEDURE PowerOfTwo(exponent: INTEGER): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    result := 1.0D0;
    WHILE exponent > 0 DO result := result * 2.0D0; DEC(exponent) END;
    RETURN result
  END PowerOfTwo;

  (* v * 2^e, exact whenever the result is representable: never a step of
     more than 2^1000, so no intermediate result is out of range unless the
     answer is. *)
  PROCEDURE ScaleByPowerOfTwo(v: LONGREAL; e: INTEGER): LONGREAL;
    VAR big: LONGREAL;
  BEGIN
    big := PowerOfTwo(1000);
    WHILE e > 1000 DO v := v * big; DEC(e, 1000) END;
    WHILE e < -1000 DO v := v / big; INC(e, 1000) END;
    IF e >= 0 THEN RETURN v * PowerOfTwo(e) ELSE RETURN v / PowerOfTwo(-e) END
  END ScaleByPowerOfTwo;

  (* a := a DIV d, for 0 < d < limbBase, and the remainder. *)
  PROCEDURE DivSmall(VAR a: Big; d: LONGINT; VAR remainder: LONGINT);
    VAR i: INTEGER; t: LONGINT;
  BEGIN
    remainder := 0; i := a.n - 1;
    WHILE i >= 0 DO
      t := remainder * limbBase + a.limb[i];
      a.limb[i] := t DIV d;
      remainder := t MOD d;
      DEC(i)
    END;
    Trim(a)
  END DivSmall;

  (* The decimal digits of v > 0, rounded to precision significant digits
     (nearest, ties to even) and set in digits[0 .. precision - 1] with a
     terminating 0X after them: v is then about d0.d1d2... * 10^exponent10.
     v = m * 2^e exactly, and m * 2^e is the integer m * 2^e when e >= 0 and
     the integer m * 5^-e read with the decimal point -e places from the end
     when e < 0, so the exact decimal expansion (up to 770 digits for the
     smallest subnormal) is just the digits of a big integer, taken four at a
     time by dividing by 10000; the rounding then looks at the exact digits
     after the last one kept. digits must have room for precision + 1
     characters. *)
  PROCEDURE Digits*(v: LONGREAL; precision: INTEGER; VAR digits: ARRAY OF CHAR;
                    VAR exponent10: INTEGER);
    VAR
      n: Big; m, group, remainder: LONGINT; e, i, count, pointShift: INTEGER;
      all: ARRAY 900 OF CHAR; low: ARRAY 4 OF CHAR;
      limit: LONGREAL; up, anyBelow: BOOLEAN; d: INTEGER;
  BEGIN
    (* v = m * 2^e with m an integer below 2^53 (below 2^52 only for the
       smallest binades: e stays at -1074) *)
    e := 0; limit := PowerOfTwo(53);
    WHILE v >= limit DO v := v / 2.0D0; INC(e) END;
    limit := PowerOfTwo(52);
    WHILE (v < limit) & (e > minExponent) DO v := v * 2.0D0; DEC(e) END;
    m := ENTIER(v);
    n.n := 0;
    (* n := m *)
    WHILE m > 0 DO
      n.limb[n.n] := m MOD limbBase; m := m DIV limbBase; INC(n.n)
    END;
    IF e >= 0 THEN
      ShiftLeft(n, e); pointShift := 0
    ELSE
      MulPower5(n, -e); pointShift := e
    END;
    (* the digits of n, most significant first, in all[0 .. count - 1] *)
    count := 0;
    WHILE n.n > 0 DO
      DivSmall(n, 10000, remainder);
      i := 0;
      WHILE i < 4 DO
        low[i] := CHR(ORD("0") + SHORT(remainder MOD 10)); remainder := remainder DIV 10; INC(i)
      END;
      i := 0;
      WHILE i < 4 DO all[count] := low[i]; INC(count); INC(i) END
    END;
    (* the groups came out least significant first, each reversed: drop the
       leading zeros of the top group and reverse the whole string *)
    WHILE (count > 1) & (all[count - 1] = "0") DO DEC(count) END;
    i := 0;
    WHILE i < count DIV 2 DO
      low[0] := all[i]; all[i] := all[count - 1 - i]; all[count - 1 - i] := low[0]; INC(i)
    END;
    exponent10 := count - 1 + pointShift;
    (* round to precision digits *)
    up := FALSE;
    IF count > precision THEN
      d := ORD(all[precision]) - ORD("0");
      anyBelow := FALSE; i := precision + 1;
      WHILE i < count DO IF all[i] # "0" THEN anyBelow := TRUE END; INC(i) END;
      IF d > 5 THEN up := TRUE
      ELSIF d = 5 THEN up := anyBelow OR ODD(ORD(all[precision - 1]) - ORD("0"))
      END
    END;
    i := 0;
    WHILE i < precision DO
      IF i < count THEN digits[i] := all[i] ELSE digits[i] := "0" END;
      INC(i)
    END;
    digits[precision] := 0X;
    IF up THEN
      i := precision - 1;
      WHILE (i >= 0) & (digits[i] = "9") DO digits[i] := "0"; DEC(i) END;
      IF i >= 0 THEN
        digits[i] := CHR(ORD(digits[i]) + 1)
      ELSE (* every digit was 9: 10^precision, i.e. 1 then zeros *)
        digits[0] := "1"; INC(exponent10)
      END
    END
  END Digits;

  (* The number nearest the non-negative numeral lexeme - digits, an
     optional fraction, an optional "E" or "D" exponent with an optional
     sign: what Lexer.Mod produces for a real numeral - of precision bits,
     whose smallest subnormal's last bit has binary exponent lowest and
     whose largest finite value has a last bit of exponent highest: a
     LONGREAL's (53, -1074, 971), or a REAL's (24, -149, 104), returned in
     a LONGREAL, which holds it exactly. *)
  PROCEDURE ParseRounded(lexeme: ARRAY OF CHAR; precision, lowest, highest: INTEGER): LONGREAL;
    VAR
      digits, left, factor, product, twice: Big;
      i, kept, exponent10, magnitude, estimate, e, bits: INTEGER;
      d, q, m: LONGINT;
      inFraction, sticky, negativeExponent: BOOLEAN;
      cmp: INTEGER;
      huge: LONGREAL;
  BEGIN
    digits.n := 0; kept := 0; exponent10 := 0; sticky := FALSE;
    i := 0; inFraction := FALSE;
    WHILE ((lexeme[i] >= "0") & (lexeme[i] <= "9")) OR ((lexeme[i] = ".") & ~inFraction) DO
      IF lexeme[i] = "." THEN
        inFraction := TRUE
      ELSE
        d := ORD(lexeme[i]) - ORD("0");
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
    IF (lexeme[i] = "E") OR (lexeme[i] = "D") THEN
      INC(i); negativeExponent := FALSE;
      IF lexeme[i] = "-" THEN negativeExponent := TRUE; INC(i)
      ELSIF lexeme[i] = "+" THEN INC(i)
      END;
      e := 0;
      WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
        IF e < 30000 THEN e := e * 10 + (ORD(lexeme[i]) - ORD("0")) END;
        INC(i)
      END;
      IF negativeExponent THEN exponent10 := exponent10 - e ELSE exponent10 := exponent10 + e END
    END;
    IF digits.n = 0 THEN RETURN 0.0D0 END;
    IF sticky THEN MulAdd(digits, 10, 1); INC(kept); DEC(exponent10) END;
    (* the value is in [10^(magnitude - 1), 10^magnitude) *)
    magnitude := kept + exponent10;
    IF magnitude > 310 THEN
      huge := PowerOfTwo(1000);
      RETURN huge * huge
    ELSIF magnitude < -330 THEN
      RETURN 0.0D0
    END;

    (* a lower bound of the binary exponent e for which V / 2^e has
       precision bits, and one bit to spare for the estimate's own error *)
    estimate := SHORT(ENTIER((magnitude - 1) * 3.321928094887362D0));
    e := estimate - precision;
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
    (* q * 2^e <= V < (q + 1) * 2^e, and q has precision bits (or e is the
       smallest): round to nearest, ties to even, by comparing 2 * left with
       (2q + 1) * factor *)
    Copy(left, twice); MulAdd(twice, 2, 0);
    MulLong(factor, 2 * q + 1, product);
    cmp := Compare(twice, product);
    IF (cmp > 0) OR ((cmp = 0) & ODD(q)) THEN m := q + 1 ELSE m := q END;
    IF BitLength(m) > precision THEN (* rounded up: exactly 2^(precision - 1) * 2^(e + 1) *)
      m := m DIV 2; INC(e)
    END;
    IF e > highest THEN
      huge := PowerOfTwo(1000);
      RETURN huge * huge
    END;
    RETURN ScaleByPowerOfTwo(m, e)
  END ParseRounded;

  (* The LONGREAL nearest the numeral lexeme (as ParseRounded) *)
  PROCEDURE Parse*(lexeme: ARRAY OF CHAR): LONGREAL;
  BEGIN
    RETURN ParseRounded(lexeme, 53, minExponent, 971)
  END Parse;

  (* The REAL nearest the numeral lexeme, held in a LONGREAL (Phase 14: an
     element of a record or array constant, written into an LLVM constant,
     which cannot round a decimal itself) - not the LONGREAL nearest it
     rounded again, which can differ *)
  PROCEDURE ParseSingle*(lexeme: ARRAY OF CHAR): LONGREAL;
  BEGIN
    RETURN ParseRounded(lexeme, 24, -149, 104)
  END ParseSingle;


END DecimalToDouble.
