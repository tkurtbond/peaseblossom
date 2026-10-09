MODULE VaxShortLongAsh;
  (* PLAN.md Phase 15 step 7b: SHORT, LONG and ASH (the design's section
     8). SHORT keeps the low bytes, CVTLW or CVTWB, or a HUGEINT's low
     longword; LONG sign-extends, CVTBW or CVTWL. ASH(x, n) is ASHL, or
     ASHQ for a HUGEINT x, in the wider of LONGINT and x's type; a shift of
     the width or more leaves 0, or the sign for a right one, and an n
     wider than a SHORTINT is first limited to -64..64, ASHL's count being a
     byte. *)

  PROCEDURE ShortL(l: LONGINT): INTEGER;
  BEGIN RETURN SHORT(l)
  END ShortL;

  PROCEDURE ShortI(i: INTEGER): SHORTINT;
  BEGIN RETURN SHORT(i)
  END ShortI;

  PROCEDURE ShortH(h: HUGEINT): LONGINT;
  BEGIN RETURN SHORT(h)
  END ShortH;

  PROCEDURE LongB(b: SHORTINT): INTEGER;
  BEGIN RETURN LONG(b)
  END LongB;

  PROCEDURE LongI(i: INTEGER): LONGINT;
  BEGIN RETURN LONG(i)
  END LongI;

  PROCEDURE LongH(h: HUGEINT; VAR r: HUGEINT);
  BEGIN r := LONG(h)
  END LongH;

  PROCEDURE Ash(x: LONGINT; n: INTEGER): LONGINT;
  BEGIN RETURN ASH(x, n)
  END Ash;

  PROCEDURE AshB(x: INTEGER; n: SHORTINT): LONGINT;
  BEGIN RETURN ASH(x, n)
  END AshB;

  PROCEDURE AshConstant(x: LONGINT): LONGINT;
  BEGIN RETURN ASH(x, 3) + ASH(x, -100)
  END AshConstant;

  PROCEDURE AshH(VAR r: HUGEINT; x: HUGEINT; n: LONGINT);
  BEGIN r := ASH(x, n)
  END AshH;

  PROCEDURE AshHN(x: LONGINT; n: HUGEINT): LONGINT;
  BEGIN RETURN ASH(x, n)
  END AshHN;

END VaxShortLongAsh.
