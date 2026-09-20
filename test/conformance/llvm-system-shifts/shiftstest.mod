MODULE shiftstest;
  (* PLAN.md Phase 10 step 7: SYSTEM.LSH, SYSTEM.ROT and SYSTEM.BIT, on the
     counts and types where voc's are defined (test.sh runs this same
     source under both and requires the same output; llvm-system-extra has
     a count of the width or more, CHAR and BYTE operands, and a bit
     number out of range). A logical shift fills with zeros at the width of
     the operand's own type - under -O2 SHORTINT is 8 bits, INTEGER 16,
     LONGINT 32 - so LSH(-1, -1) is the largest number of the type. *)
  IMPORT SYSTEM, Out;

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT;
    word: LONGINT; bytes: ARRAY 8 OF SHORTINT;

  PROCEDURE Show(x: HUGEINT);
  BEGIN Out.Int(x, 0); Out.Char(" ") END Show;

  PROCEDURE Bit(b: BOOLEAN);
  BEGIN IF b THEN Out.Char("1") ELSE Out.Char("0") END END Bit;

  PROCEDURE Shifts;
  BEGIN
    l := -1;
    Show(SYSTEM.LSH(l, -1)); Show(SYSTEM.LSH(l, 4)); Show(SYSTEM.LSH(l, -28)); Out.Ln;
    l := 1;
    Show(SYSTEM.LSH(l, 31)); Show(SYSTEM.LSH(l, 30)); Show(SYSTEM.LSH(l, 0)); Out.Ln;
    l := 12345678H;
    Show(SYSTEM.LSH(l, 4)); Show(SYSTEM.LSH(l, -4)); Show(SYSTEM.LSH(l, 8)); Show(SYSTEM.LSH(l, -16)); Out.Ln;
    s := -1;
    Show(SYSTEM.LSH(s, -1)); Show(SYSTEM.LSH(s, 1)); Show(SYSTEM.LSH(s, -7)); Show(SYSTEM.LSH(s, 7)); Out.Ln;
    s := -127; (* 81H *)
    Show(SYSTEM.LSH(s, -7)); Show(SYSTEM.LSH(s, 1)); Out.Ln;
    i := -1;
    Show(SYSTEM.LSH(i, -1)); Show(SYSTEM.LSH(i, 1)); Show(SYSTEM.LSH(i, -15)); Out.Ln;
    i := 4000H;
    Show(SYSTEM.LSH(i, 1)); Show(SYSTEM.LSH(i, -14)); Out.Ln;
    h := -1;
    Show(SYSTEM.LSH(h, -1)); Show(SYSTEM.LSH(h, -63)); Show(SYSTEM.LSH(h, 62)); Out.Ln;
    h := 1;
    Show(SYSTEM.LSH(h, 63)); Show(SYSTEM.LSH(h, 32)); Out.Ln;
    (* numerals have the smallest type their value fits *)
    Show(SYSTEM.LSH(1, 3)); Show(SYSTEM.LSH(100, 1)); Show(SYSTEM.LSH(3, -1)); Out.Ln
  END Shifts;

  PROCEDURE Rotations;
  BEGIN
    l := 1;
    Show(SYSTEM.ROT(l, 31)); Show(SYSTEM.ROT(l, -1)); Show(SYSTEM.ROT(l, 0)); Show(SYSTEM.ROT(l, 1)); Out.Ln;
    l := 12345678H;
    Show(SYSTEM.ROT(l, 8)); Show(SYSTEM.ROT(l, -8)); Show(SYSTEM.ROT(l, 16)); Show(SYSTEM.ROT(l, 4)); Out.Ln;
    s := -1;
    Show(SYSTEM.ROT(s, 1)); Show(SYSTEM.ROT(s, -3)); Out.Ln;
    s := -127; (* 81H *)
    Show(SYSTEM.ROT(s, 1)); Show(SYSTEM.ROT(s, -1)); Show(SYSTEM.ROT(s, 4)); Out.Ln;
    i := 4000H;
    Show(SYSTEM.ROT(i, 2)); Show(SYSTEM.ROT(i, -14)); Show(SYSTEM.ROT(i, 15)); Out.Ln;
    h := 1;
    Show(SYSTEM.ROT(h, 63)); Show(SYSTEM.ROT(h, -1)); Show(SYSTEM.ROT(h, 1)); Out.Ln;
    Show(SYSTEM.ROT(1, 7)); Show(SYSTEM.ROT(1, -1)); Out.Ln
  END Rotations;

  PROCEDURE Bits;
    VAR k: INTEGER;
  BEGIN
    (* the low bit first, in the word's own order *)
    word := 5;
    FOR k := 0 TO 5 DO Bit(SYSTEM.BIT(SYSTEM.ADR(word), k)) END; Out.Ln;
    word := MIN(LONGINT);
    Bit(SYSTEM.BIT(SYSTEM.ADR(word), 31)); Bit(SYSTEM.BIT(SYSTEM.ADR(word), 30));
    Bit(SYSTEM.BIT(SYSTEM.ADR(word), 7)); Bit(SYSTEM.BIT(SYSTEM.ADR(word), 0)); Out.Ln;
    word := 0;
    FOR k := 0 TO 31 DO Bit(SYSTEM.BIT(SYSTEM.ADR(word), k)) END; Out.Ln;
    word := -1;
    FOR k := 0 TO 31 DO Bit(SYSTEM.BIT(SYSTEM.ADR(word), k)) END; Out.Ln;
    (* any address will do, not only a variable's own: an element *)
    FOR k := 0 TO 7 DO bytes[k] := 0 END; bytes[1] := 8;
    Bit(SYSTEM.BIT(SYSTEM.ADR(bytes[1]), 3)); Bit(SYSTEM.BIT(SYSTEM.ADR(bytes[1]), 2));
    Bit(SYSTEM.BIT(SYSTEM.ADR(bytes[0]), 11)); Bit(SYSTEM.BIT(SYSTEM.ADR(bytes[0]), 10)); Out.Ln
  END Bits;

BEGIN
  Shifts;
  Rotations;
  Bits
END shiftstest.
