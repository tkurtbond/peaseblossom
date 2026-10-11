MODULE system;
  (* PLAN.md Phase 9 step 4's compile+link+run+diff fixture for the SYSTEM
     subset: ADDRESS, ADR, GET, PUT, VAL, MOVE. Each check prints
     "FAIL nn " on failure; the run ends with "OK" if none did.
     Everything before the "poc-only" marker also runs, and passes, under
     real voc: the two checks after it
     are VAL between integers of different widths, which Oberon2.pdf
     leaves undefined (voc even warns) and poc defines as sign-extension
     and truncation.
     Everything is spelled with explicitly typed variables so the same
     checks mean the same thing under -O2 and -OC (a PUT stores its
     argument at that argument's own type). *)
  IMPORT SYSTEM, Out;
  TYPE
    Pair = RECORD a, b: INTEGER END;
    PairRef = POINTER TO Pair;
  VAR
    addr, other: SYSTEM.ADDRESS;
    i, j, k: INTEGER;
    l, m: LONGINT;
    h: HUGEINT;
    c, d: CHAR;
    r, r2: REAL;
    x, y: LONGREAL;
    s, t: SET;
    flag: BOOLEAN;
    buf: ARRAY 16 OF CHAR;
    ints: ARRAY 8 OF INTEGER;
    more: ARRAY 8 OF INTEGER;
    pair: Pair;

  PROCEDURE AddressOf(VAR v: INTEGER): SYSTEM.ADDRESS;
  BEGIN
    RETURN SYSTEM.ADR(v)
  END AddressOf;

  PROCEDURE Bump(a: SYSTEM.ADDRESS);
    VAR v: INTEGER;
  BEGIN
    SYSTEM.GET(a, v); INC(v); SYSTEM.PUT(a, v)
  END Bump;

BEGIN
  (* ADR / GET / PUT on scalars *)
  i := 1234;
  addr := SYSTEM.ADR(i);
  SYSTEM.GET(addr, j);
  IF j # 1234 THEN Out.String("FAIL 01 ") END;
  k := 99;
  SYSTEM.PUT(addr, k);
  IF i # 99 THEN Out.String("FAIL 02 ") END;
  IF SYSTEM.ADR(i) # addr THEN Out.String("FAIL 03 ") END;
  IF SYSTEM.ADR(i) = SYSTEM.ADR(j) THEN Out.String("FAIL 04 ") END;
  Bump(addr);
  IF i # 100 THEN Out.String("FAIL 05 ") END;
  IF AddressOf(j) # SYSTEM.ADR(j) THEN Out.String("FAIL 06 ") END;
  (* other basic types *)
  l := 123456789; addr := SYSTEM.ADR(l); SYSTEM.GET(addr, m);
  IF m # 123456789 THEN Out.String("FAIL 07 ") END;
  h := 1234567890123; addr := SYSTEM.ADR(h);
  h := 0; SYSTEM.GET(SYSTEM.ADR(h), h);
  c := "q"; SYSTEM.GET(SYSTEM.ADR(c), d);
  IF d # "q" THEN Out.String("FAIL 08 ") END;
  SYSTEM.PUT(SYSTEM.ADR(d), c);
  r := 2.5; SYSTEM.GET(SYSTEM.ADR(r), r2);
  IF r2 # 2.5 THEN Out.String("FAIL 09 ") END;
  x := 0.125D0; y := 0.0D0; SYSTEM.GET(SYSTEM.ADR(x), y);
  IF y # 0.125D0 THEN Out.String("FAIL 10 ") END;
  s := {1, 5, 9}; SYSTEM.GET(SYSTEM.ADR(s), t);
  IF t # {1, 5, 9} THEN Out.String("FAIL 11 ") END;
  flag := TRUE; SYSTEM.PUT(SYSTEM.ADR(flag), FALSE);
  IF flag THEN Out.String("FAIL 12 ") END;
  (* array elements and record fields *)
  FOR i := 0 TO 7 DO ints[i] := i * 10 END;
  addr := SYSTEM.ADR(ints[0]);
  SYSTEM.GET(SYSTEM.ADR(ints[3]), j);
  IF j # 30 THEN Out.String("FAIL 13 ") END;
  SYSTEM.GET(addr + 5 * SIZE(INTEGER), j);
  IF j # 50 THEN Out.String("FAIL 14 ") END;
  k := 77;
  SYSTEM.PUT(addr + 2 * SIZE(INTEGER), k);
  IF ints[2] # 77 THEN Out.String("FAIL 15 ") END;
  pair.a := 5; pair.b := 6;
  SYSTEM.GET(SYSTEM.ADR(pair.b), j);
  IF j # 6 THEN Out.String("FAIL 16 ") END;
  IF SYSTEM.ADR(pair.b) - SYSTEM.ADR(pair.a) # SIZE(INTEGER) THEN Out.String("FAIL 17 ") END;
  (* ADDRESS arithmetic and comparison *)
  addr := 1000; other := addr + 24;
  IF (other - addr # 24) OR ~(addr < other) OR (addr > other) THEN Out.String("FAIL 18 ") END;
  i := 5; addr := addr + i; l := 3; addr := addr + l;
  IF addr # 1008 THEN Out.String("FAIL 19 ") END;
  h := addr; IF h # 1008 THEN Out.String("FAIL 20 ") END;
  IF SIZE(SYSTEM.ADDRESS) # SIZE(PairRef) THEN Out.String("FAIL 21 ") END;
  (* VAL *)
  l := -2; m := SYSTEM.VAL(LONGINT, l);
  IF m # -2 THEN Out.String("FAIL 22 ") END;
  i := SYSTEM.VAL(INTEGER, 4660);
  IF i # 4660 THEN Out.String("FAIL 23 ") END;
  addr := SYSTEM.ADR(i);
  h := SYSTEM.VAL(HUGEINT, addr);
  IF SYSTEM.VAL(SYSTEM.ADDRESS, h) # addr THEN Out.String("FAIL 24 ") END;
  s := SYSTEM.VAL(SET, 5);
  IF s # {0, 2} THEN Out.String("FAIL 25 ") END;
  i := SYSTEM.VAL(INTEGER, s);
  IF i # 5 THEN Out.String("FAIL 26 ") END;
  c := SYSTEM.VAL(CHAR, 65);
  IF c # "A" THEN Out.String("FAIL 27 ") END;
  (* MOVE *)
  FOR i := 0 TO 7 DO ints[i] := i + 1; more[i] := 0 END;
  SYSTEM.MOVE(SYSTEM.ADR(ints[0]), SYSTEM.ADR(more[0]), 8 * SIZE(INTEGER));
  k := 0; FOR i := 0 TO 7 DO k := k + more[i] END;
  IF k # 36 THEN Out.String("FAIL 28 ") END;
  (* overlapping, forward and backward *)
  SYSTEM.MOVE(SYSTEM.ADR(ints[0]), SYSTEM.ADR(ints[2]), 6 * SIZE(INTEGER));
  IF (ints[0] # 1) OR (ints[1] # 2) OR (ints[2] # 1) OR (ints[3] # 2) OR (ints[7] # 6) THEN Out.String("FAIL 29 ") END;
  SYSTEM.MOVE(SYSTEM.ADR(ints[2]), SYSTEM.ADR(ints[0]), 6 * SIZE(INTEGER));
  IF (ints[0] # 1) OR (ints[1] # 2) OR (ints[5] # 6) OR (ints[7] # 6) THEN Out.String("FAIL 30 ") END;
  SYSTEM.MOVE(SYSTEM.ADR(ints[0]), SYSTEM.ADR(more[0]), 0);
  SYSTEM.MOVE(SYSTEM.ADR(ints[0]), SYSTEM.ADR(more[0]), -5);
  IF more[0] # 1 THEN Out.String("FAIL 31 ") END;
  (* a character buffer *)
  COPY("hello", buf);
  SYSTEM.MOVE(SYSTEM.ADR(buf[0]), SYSTEM.ADR(buf[8]), 6);
  IF (buf[8] # "h") OR (buf[12] # "o") OR (buf[13] # 0X) THEN Out.String("FAIL 32 ") END;
  (* poc-only *)
  i := -2; l := SYSTEM.VAL(LONGINT, i);
  IF l # -2 THEN Out.String("FAIL 33 ") END;
  l := 65536 + 7; i := SYSTEM.VAL(INTEGER, l);
  IF i # 7 THEN Out.String("FAIL 34 ") END;
  Out.String("OK")
END system.
