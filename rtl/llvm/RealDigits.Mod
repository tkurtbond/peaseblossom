MODULE RealDigits;

  (* Phase 11 step 2 (inventory A3): the exact decimal digits of a LONGREAL,
     correctly rounded to any number of significant digits - what Out.Real
     and Out.LongReal print from. Not part of the Oakwood library; an
     internal module of the runtime, like GarbageCollectedHeap.

     v = m * 2^e exactly, m an integer below 2^53 and e >= -1074 (both read
     from v's bits), and m * 2^e is the integer m * 2^e when e >= 0 and the
     integer m * 5^-e with the decimal point -e places from the end when e < 0
     (10^-e = 2^-e * 5^-e), so the exact decimal expansion - up to 770 digits
     for the smallest subnormal - is just the digits of a big integer, taken
     four at a time by dividing by 10000. Rounding to n digits looks at the
     exact digits after the n-th: up if the first is above 5 or is 5 with a
     nonzero digit after it, to even on an exact tie.

     No floating-point arithmetic is done at all, so the result cannot depend
     on the host's precision, and every quantity is a HUGEINT, so nor can it
     depend on the size model (LONGINT is 4 bytes under -O2 and 8 under -OC).
     The big integers are 15-bit limbs; a product of two is below 2^30.

     src/front/DecimalToDouble.Mod has the same algorithm in strict
     Oberon-2 for the compiler's own use: poc's own source uses no extension
     (HUGEINT, SYSTEM), and Stage 0 builds it with voc, which has no
     counterpart of a new runtime module to link it against. The two are kept
     in step by the fixtures of both (llvm-real-digits,
     module-interface-extreme-reals). *)

  IMPORT SYSTEM;

  CONST
    limbBase = 32768;
    maxLimbs = 400; (* 6000 bits; the largest number here is under 2600 *)
    minExponent = -1074;
    mantissaTop = 10000000000000H; (* 2^52 *)

  TYPE
    (* limb[0] is the least significant; n limbs are in use *)
    Big = RECORD
      n: INTEGER;
      limb: ARRAY maxLimbs OF HUGEINT
    END;

  (* a := a * m + c, for 0 <= m < limbBase and 0 <= c < limbBase *)
  PROCEDURE MulAdd(VAR a: Big; m, c: HUGEINT);
    VAR i: INTEGER; carry, t: HUGEINT;
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
  PROCEDURE MulPower5(VAR a: Big; k: INTEGER);
    VAR factor: HUGEINT;
  BEGIN
    WHILE k >= 6 DO MulAdd(a, 15625, 0); DEC(k, 6) END;
    IF k > 0 THEN
      factor := 1;
      WHILE k > 0 DO factor := factor * 5; DEC(k) END;
      MulAdd(a, factor, 0)
    END
  END MulPower5;

  (* a := a DIV d, for 0 < d < limbBase; the remainder is returned *)
  PROCEDURE DivSmall(VAR a: Big; d: HUGEINT): HUGEINT;
    VAR i: INTEGER; t, remainder: HUGEINT;
  BEGIN
    remainder := 0; i := a.n - 1;
    WHILE i >= 0 DO
      t := remainder * limbBase + a.limb[i];
      a.limb[i] := t DIV d;
      remainder := t MOD d;
      DEC(i)
    END;
    WHILE (a.n > 0) & (a.limb[a.n - 1] = 0) DO DEC(a.n) END;
    RETURN remainder
  END DivSmall;

  (* The digits of v > 0 (finite), rounded to precision significant digits
     (nearest, ties to even), in digits[0 .. precision - 1] followed by 0X:
     v is about d0.d1d2... * 10^exponent10. digits has room for precision + 1
     characters. *)
  PROCEDURE Digits*(v: LONGREAL; precision: INTEGER; VAR digits: ARRAY OF CHAR;
                    VAR exponent10: INTEGER);
    VAR
      n: Big; bits, m, group: HUGEINT; biased, e, i, j, count, pointShift, d: INTEGER;
      all: ARRAY 800 OF CHAR;
      up, anyBelow: BOOLEAN; swap: CHAR;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, v);
    biased := SYSTEM.VAL(INTEGER, (bits DIV mantissaTop) MOD 800H);
    m := bits MOD mantissaTop;
    IF biased = 0 THEN e := minExponent ELSE m := m + mantissaTop; e := biased - 1075 END;
    n.n := 0;
    WHILE m > 0 DO
      n.limb[n.n] := m MOD limbBase; m := m DIV limbBase; INC(n.n)
    END;
    IF e >= 0 THEN
      ShiftLeft(n, e); pointShift := 0
    ELSE
      MulPower5(n, -e); pointShift := e
    END;
    (* all[0 ..] gets the digits least significant first, four per division *)
    count := 0;
    WHILE n.n > 0 DO
      group := DivSmall(n, 10000);
      i := 0;
      WHILE i < 4 DO
        all[count] := CHR(SYSTEM.VAL(INTEGER, group MOD 10) + 48); group := group DIV 10;
        INC(count); INC(i)
      END
    END;
    WHILE (count > 1) & (all[count - 1] = "0") DO DEC(count) END;
    i := 0; j := count - 1;
    WHILE i < j DO swap := all[i]; all[i] := all[j]; all[j] := swap; INC(i); DEC(j) END;
    exponent10 := count - 1 + pointShift;

    up := FALSE;
    IF count > precision THEN
      d := ORD(all[precision]) - 48;
      anyBelow := FALSE; i := precision + 1;
      WHILE i < count DO IF all[i] # "0" THEN anyBelow := TRUE END; INC(i) END;
      IF d > 5 THEN up := TRUE
      ELSIF d = 5 THEN up := anyBelow OR ODD(ORD(all[precision - 1]) - 48)
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
      ELSE (* every digit was 9: 10^precision *)
        digits[0] := "1"; INC(exponent10)
      END
    END
  END Digits;

END RealDigits.
