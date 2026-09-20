MODULE fixed;
  (* SYSTEM.INT8/INT16/INT32/INT64 are exactly 1/2/4/8 bytes under -O2 and
     -OC alike (LONGINT is 4 under -O2, 8 under -OC): sizes, bounds, values
     stored in and read back from a record of them, values crossing to and
     from the model's own integer types, and a C function taking and
     returning an int - which is INT32 on every target. Its declaration
     used to be written LONGINT, a 64-bit int under -OC: right by luck on
     x86-64, wrong on a 32-bit target's stack. *)
  IMPORT SYSTEM, Out;

  TYPE
    Packed = RECORD
      a: SYSTEM.INT8; b: SYSTEM.INT16; c: SYSTEM.INT32
    END;

  VAR
    b: SYSTEM.INT8; h: SYSTEM.INT16; i: SYSTEM.INT32; q: SYSTEM.INT64;
    l: LONGINT; u: HUGEINT;
    p: Packed;

  PROCEDURE ["C", "abs"] CAbs(x: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Line(name: ARRAY OF CHAR; value: HUGEINT);
  BEGIN
    Out.String(name); Out.String(" = "); Out.Int(value, 0); Out.Ln
  END Line;

BEGIN
  Line("SIZE(INT8)", SIZE(SYSTEM.INT8)); Line("SIZE(INT16)", SIZE(SYSTEM.INT16));
  Line("SIZE(INT32)", SIZE(SYSTEM.INT32)); Line("SIZE(INT64)", SIZE(SYSTEM.INT64));
  Line("SIZE(LONGINT)", SIZE(LONGINT));
  Line("MIN(INT8)", MIN(SYSTEM.INT8)); Line("MAX(INT8)", MAX(SYSTEM.INT8));
  Line("MIN(INT16)", MIN(SYSTEM.INT16)); Line("MAX(INT16)", MAX(SYSTEM.INT16));
  Line("MIN(INT32)", MIN(SYSTEM.INT32)); Line("MAX(INT32)", MAX(SYSTEM.INT32));
  Line("MIN(INT64)", MIN(SYSTEM.INT64)); Line("MAX(INT64)", MAX(SYSTEM.INT64));

  b := -100; h := -30000; i := -2000000000; q := -9000000000000000000;
  Line("b", b); Line("h", h); Line("i", i); Line("q", q);
  l := i; Line("LONGINT from INT32", l);
  u := q; Line("HUGEINT from INT64", u);
  q := l; Line("INT64 from LONGINT", q);
  h := b; i := h; q := i;
  Line("widened b -> h -> i -> q", q);

  p.a := 127; p.b := 32767; p.c := 2147483647;
  Line("p.a", p.a); Line("p.b", p.b); Line("p.c", p.c);
  p.a := -128; p.b := -32768; p.c := -2147483647 - 1;
  Line("p.a", p.a); Line("p.b", p.b); Line("p.c", p.c);

  (* arithmetic done at the operands' own width, results kept in range *)
  i := 40000; i := i * 30000;
  Line("40000 * 30000 in INT32", i);
  i := 1000000; i := i DIV 7 + i MOD 7;
  Line("1000000 DIV 7 + 1000000 MOD 7", i);
  (* an INT8 met by an integer literal is not kept at INT8 under -OC (the
     literal's own type is at least SHORTINT's two bytes there), so narrow
     with VAL *)
  b := 100; h := b;
  b := SYSTEM.VAL(SYSTEM.INT8, h - 150);
  Line("100 - 150 in INT8", b);

  (* the C int: sign and width both survive the call *)
  Line("abs(-5)", CAbs(-5));
  Line("abs(2147483647)", CAbs(2147483647));
  i := -123456; Line("abs(-123456)", CAbs(i));
  l := CAbs(-77); Line("abs(-77) in a LONGINT", l)
END fixed.
