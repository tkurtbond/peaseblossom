MODULE sets;
  (* PLAN.md Phase 9 step 3's compile+link+run+diff fixture for SET: the
     constructor (single elements, ranges, an empty range (lo > hi, non-constant: voc rejects a constant one), non-constant
     elements), IN, the four operators, unary minus, = and #, INCL/EXCL,
     a SET constant, and SETs carried through parameters, results, array
     elements and record fields. Elements of three integer widths, since
     an element has to be converted to the SET's own width before it is
     shifted. Each check prints "FAIL nn " on failure; the run ends
     with "OK" if none did.

     Everything before the "poc-only" marker also runs, and passes,
     under real voc (SysWrite swapped for Out.String). The three checks
     after it are IN with an element outside 0..MAX(SET): Oberon2.pdf
     leaves that undefined and voc's C (a plain shift) does too, but
     poc's IN is defined to be FALSE there rather than an LLVM poison
     value, and this pins it. A SET is 32 bits under -O2 and -OC
     alike (voc's, and Component Pascal's), so test.sh builds and runs the
     program under both and the output must be the same - checks 14 and 19,
     whose complements are {0 .. 31} and {31}, would differ under a 64-bit
     SET. *)
  IMPORT SYSTEM;
  CONST
    evens = {0, 2, 4, 6};
  VAR
    s, t, u, v, w, empty: SET;
    a: ARRAY 3 OF SET;
    rec: RECORD members: SET END;
    i, count: INTEGER;
    sh: SHORTINT;
    li: LONGINT;
  PROCEDURE ["C", "write"] SysWrite(fd: SYSTEM.INT32; s: ARRAY OF CHAR; n: SYSTEM.ADDRESS);
  (* the C types: a LONGINT is 8 bytes under -OC, which shifts the arguments of a
     32-bit target's write *)

  PROCEDURE Union(x, y: SET): SET;
  BEGIN
    RETURN x + y
  END Union;

  PROCEDURE SetOf(x: LONGINT): SET;
  BEGIN
    RETURN {x}
  END SetOf;

BEGIN
  s := {1, 3, 5 .. 7};
  empty := {};
  IF ~(1 IN s) THEN SysWrite(1, "FAIL 01 ", 8) END;
  IF ~(3 IN s) THEN SysWrite(1, "FAIL 02 ", 8) END;
  IF ~(5 IN s) THEN SysWrite(1, "FAIL 03 ", 8) END;
  IF ~(6 IN s) THEN SysWrite(1, "FAIL 04 ", 8) END;
  IF ~(7 IN s) THEN SysWrite(1, "FAIL 05 ", 8) END;
  IF ~(~(0 IN s)) THEN SysWrite(1, "FAIL 06 ", 8) END;
  IF ~(~(2 IN s)) THEN SysWrite(1, "FAIL 07 ", 8) END;
  IF ~(~(4 IN s)) THEN SysWrite(1, "FAIL 08 ", 8) END;
  IF ~(~(8 IN s)) THEN SysWrite(1, "FAIL 09 ", 8) END;
  IF ~(empty = {}) THEN SysWrite(1, "FAIL 10 ", 8) END;
  i := 4; t := {i, i + 1 .. i + 3};
  IF ~(t = {4, 5, 6, 7}) THEN SysWrite(1, "FAIL 11 ", 8) END;
  i := 5;
  IF ~({i .. i - 3} = {}) THEN SysWrite(1, "FAIL 12 ", 8) END;
  IF ~({3 .. 3} = {3}) THEN SysWrite(1, "FAIL 13 ", 8) END;
  IF ~({0 .. 31} = -{}) THEN SysWrite(1, "FAIL 14 ", 8) END;
  IF ~({1, 2, 3} + {3, 4} = {1, 2, 3, 4}) THEN SysWrite(1, "FAIL 15 ", 8) END;
  IF ~({1, 2, 3} - {3, 4} = {1, 2}) THEN SysWrite(1, "FAIL 16 ", 8) END;
  IF ~({1, 2, 3} * {3, 4} = {3}) THEN SysWrite(1, "FAIL 17 ", 8) END;
  IF ~({1, 2, 3} / {3, 4} = {1, 2, 4}) THEN SysWrite(1, "FAIL 18 ", 8) END;
  IF ~(-{0 .. 30} = {31}) THEN SysWrite(1, "FAIL 19 ", 8) END;
  IF ~({1, 2} # {1, 3}) THEN SysWrite(1, "FAIL 20 ", 8) END;
  IF ~(evens - {2} = {0, 4, 6}) THEN SysWrite(1, "FAIL 21 ", 8) END;
  IF ~(6 IN evens) THEN SysWrite(1, "FAIL 22 ", 8) END;
  IF ~(~(7 IN evens)) THEN SysWrite(1, "FAIL 23 ", 8) END;
  u := {2}; INCL(u, 10);
  IF ~(u = {2, 10}) THEN SysWrite(1, "FAIL 24 ", 8) END;
  v := {0, 1, 2}; EXCL(v, 1);
  IF ~(v = {0, 2}) THEN SysWrite(1, "FAIL 25 ", 8) END;
  w := {0, 1}; INCL(w, 2); EXCL(w, 30); EXCL(w, 30);
  IF ~((w = {0, 1, 2}) & (w # {})) THEN SysWrite(1, "FAIL 26 ", 8) END;
  sh := 7; li := 12; i := 4;
  IF ~((SetOf(sh) = {7}) & (SetOf(li) = {12}) & (SetOf(i) = {4})) THEN SysWrite(1, "FAIL 27 ", 8) END;
  IF ~(Union({1}, {2}) = {1, 2}) THEN SysWrite(1, "FAIL 28 ", 8) END;
  a[1] := {5}; a[2] := a[1] + {6}; a[0] := {};
  IF ~((a[1] = {5}) & (a[2] = {5, 6}) & (a[0] = {})) THEN SysWrite(1, "FAIL 29 ", 8) END;
  rec.members := {3}; INCL(rec.members, 9);
  IF ~((rec.members = {3, 9}) & (9 IN rec.members)) THEN SysWrite(1, "FAIL 30 ", 8) END;
  count := 0; FOR i := 0 TO 31 DO IF i IN t THEN INC(count) END END;
  IF ~(count = 4) THEN SysWrite(1, "FAIL 31 ", 8) END;
  IF ~((1 IN s) & (3 IN s) OR (0 IN s)) THEN SysWrite(1, "FAIL 32 ", 8) END;
  (* poc-only *)
  IF ~(~(-1 IN s)) THEN SysWrite(1, "FAIL 33 ", 8) END;
  IF ~(~(32 IN s)) THEN SysWrite(1, "FAIL 34 ", 8) END;
  IF ~(~(1000 IN s)) THEN SysWrite(1, "FAIL 35 ", 8) END;
  SysWrite(1, "OK", 2)
END sets.
