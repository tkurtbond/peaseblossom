MODULE systemextra;
  (* PLAN.md Phase 10 step 7: SYSTEM where poc's differs from voc's or voc
     leaves it undefined - a shift count of the operand's width or more, CHAR
     and BYTE operands, a bit number outside the word, PTR compared with a
     typed pointer, raw blocks from SYSTEM.NEW, and the fixed-width names.
     Poc only. Nothing printed depends on the size of a pointer. *)
  IMPORT SYSTEM, Out;

  TYPE
    Rec = RECORD a: INTEGER; b: CHAR END;
    P = POINTER TO Rec;
    Line = POINTER TO ARRAY 4 OF INTEGER;

  VAR
    l: LONGINT; h: HUGEINT; c: CHAR; b: SYSTEM.BYTE; s: SHORTINT;
    any, other: SYSTEM.PTR; p: P; line: Line;
    i8: SYSTEM.INT8; i16: SYSTEM.INT16; i32: SYSTEM.INT32; i64: SYSTEM.INT64; s32: SYSTEM.SET32;
    k, round: INTEGER; total: LONGINT;
    addr: SYSTEM.ADDRESS; value: LONGINT;

  PROCEDURE Show(x: HUGEINT);
  BEGIN Out.Int(x, 0); Out.Char(" ") END Show;

  PROCEDURE Bit(b: BOOLEAN);
  BEGIN IF b THEN Out.Char("1") ELSE Out.Char("0") END END Bit;

  PROCEDURE Yes(b: BOOLEAN);
  BEGIN IF b THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln END Yes;

  PROCEDURE Counts;
  BEGIN
    (* a count of the width or more shifts everything out; ROT is modulo *)
    l := -1;
    Show(SYSTEM.LSH(l, 32)); Show(SYSTEM.LSH(l, -32)); Show(SYSTEM.LSH(l, 40)); Show(SYSTEM.LSH(l, -1000)); Out.Ln;
    Show(SYSTEM.LSH(l, 31)); Show(SYSTEM.LSH(l, -31)); Show(SYSTEM.LSH(l, MAX(HUGEINT))); Show(SYSTEM.LSH(l, MIN(HUGEINT))); Out.Ln;
    l := 1;
    Show(SYSTEM.ROT(l, 0)); Show(SYSTEM.ROT(l, 32)); Show(SYSTEM.ROT(l, 33)); Show(SYSTEM.ROT(l, -33)); Show(SYSTEM.ROT(l, 1000)); Show(SYSTEM.ROT(l, -1000)); Out.Ln;
    Show(SYSTEM.ROT(l, MAX(HUGEINT))); Show(SYSTEM.ROT(l, MIN(HUGEINT))); Out.Ln;
    s := -127; (* 81H *)
    Show(SYSTEM.LSH(s, 8)); Show(SYSTEM.LSH(s, -8)); Show(SYSTEM.ROT(s, 8)); Show(SYSTEM.ROT(s, 9)); Show(SYSTEM.ROT(s, -9)); Out.Ln;
    h := 1;
    Show(SYSTEM.LSH(h, 64)); Show(SYSTEM.ROT(h, 64)); Show(SYSTEM.ROT(h, 65)); Show(SYSTEM.ROT(h, -65)); Out.Ln
  END Counts;

  PROCEDURE Characters;
  BEGIN
    (* a CHAR is 8 bits, unsigned: the result has the CHAR's own type *)
    c := "A"; (* 41H *)
    Show(ORD(SYSTEM.LSH(c, 1))); Show(ORD(SYSTEM.LSH(c, -1))); Show(ORD(SYSTEM.LSH(c, 7))); Show(ORD(SYSTEM.LSH(c, 8))); Out.Ln;
    Show(ORD(SYSTEM.ROT(c, 1))); Show(ORD(SYSTEM.ROT(c, -1))); Show(ORD(SYSTEM.ROT(c, 4))); Show(ORD(SYSTEM.ROT(c, 9))); Out.Ln;
    c := SYSTEM.LSH(c, 1);
    Show(ORD(c)); Out.Ln;
    (* and so is a BYTE, whose result is a BYTE *)
    b := SYSTEM.VAL(SYSTEM.BYTE, 0F0X);
    c := SYSTEM.VAL(CHAR, SYSTEM.LSH(b, -4)); Show(ORD(c));
    c := SYSTEM.VAL(CHAR, SYSTEM.LSH(b, 1)); Show(ORD(c));
    c := SYSTEM.VAL(CHAR, SYSTEM.ROT(b, 2)); Show(ORD(c));
    c := SYSTEM.VAL(CHAR, SYSTEM.ROT(b, -2)); Show(ORD(c)); Out.Ln
  END Characters;

  PROCEDURE Bits;
  BEGIN
    (* a bit number outside the word is FALSE, whatever is in memory *)
    l := -1;
    Bit(SYSTEM.BIT(SYSTEM.ADR(l), 31)); Bit(SYSTEM.BIT(SYSTEM.ADR(l), 32)); Bit(SYSTEM.BIT(SYSTEM.ADR(l), 100));
    Bit(SYSTEM.BIT(SYSTEM.ADR(l), -1)); Bit(SYSTEM.BIT(SYSTEM.ADR(l), MAX(HUGEINT))); Bit(SYSTEM.BIT(SYSTEM.ADR(l), MIN(HUGEINT)));
    Out.Ln
  END Bits;

  PROCEDURE FixedWidth;
  BEGIN
    (* under -O2, the size model poc generates code for, the fixed-width
       names are the types of that width *)
    i8 := 127; i16 := 32767; i32 := MAX(LONGINT); i64 := MAX(HUGEINT);
    Show(i8); Show(i16); Show(i32); Show(i64); Out.Ln;
    Show(MAX(SYSTEM.INT8)); Show(MIN(SYSTEM.INT16)); Show(MAX(SYSTEM.INT32)); Show(MIN(SYSTEM.INT64)); Out.Ln;
    Show(SIZE(SYSTEM.INT8)); Show(SIZE(SYSTEM.INT16)); Show(SIZE(SYSTEM.INT32)); Show(SIZE(SYSTEM.INT64)); Show(SIZE(SYSTEM.SET32)); Out.Ln;
    s := i8; l := i32; h := i64;
    i32 := l; i16 := SHORT(l MOD 100);
    Show(i16); Out.Ln;
    s32 := {0, 5, 31};
    Show(SYSTEM.LSH(SYSTEM.VAL(LONGINT, s32), -5)); Out.Ln;
    Yes(5 IN s32)
  END FixedWidth;

  PROCEDURE Pointers;
  BEGIN
    NEW(p); NEW(line);
    any := p; other := p;
    Yes(any = p); Yes(any # p); Yes(any = other); Yes(p = any);
    other := line;
    Yes(any = other); Yes(any # other); Yes(other = line);
    any := NIL;
    Yes(any = NIL); Yes(NIL = any); Yes(any # p);
    other := any;
    Yes(other = NIL)
  END Pointers;

  (* every byte of a raw block starts as 0, and it holds what is put in it *)
  PROCEDURE RawBlocks;
  BEGIN
    SYSTEM.NEW(any, 32);
    Yes(any # NIL);
    addr := SYSTEM.VAL(SYSTEM.ADDRESS, any);
    total := 0;
    FOR k := 0 TO 7 DO SYSTEM.GET(addr + 4 * k, value); total := total + ABS(value) END;
    Out.Int(total, 0); Out.Ln;
    FOR k := 0 TO 7 DO SYSTEM.PUT(addr + 4 * k, 1000 * k) END;
    total := 0;
    FOR k := 0 TO 7 DO SYSTEM.GET(addr + 4 * k, value); total := total + value END;
    Out.Int(total, 0); Out.Ln;
    SYSTEM.GET(addr + 24, value); Out.Int(value, 0); Out.Ln;
    (* into a typed pointer: the block is what the record is made of *)
    SYSTEM.NEW(p, SIZE(Rec));
    p.a := 12345; p.b := "r";
    Out.Int(p.a, 0); Out.Char(p.b); Out.Ln;
    (* a block that is no longer pointed at is reclaimed: this needs
       hundreds of megabytes if it is not *)
    FOR round := 1 TO 20000 DO
      SYSTEM.NEW(any, 100000);
      SYSTEM.PUT(SYSTEM.VAL(SYSTEM.ADDRESS, any), round)
    END;
    SYSTEM.GET(SYSTEM.VAL(SYSTEM.ADDRESS, any), value); Out.Int(value, 0); Out.Ln
  END RawBlocks;

BEGIN
  Counts;
  Characters;
  Bits;
  FixedWidth;
  Pointers;
  RawBlocks
END systemextra.
