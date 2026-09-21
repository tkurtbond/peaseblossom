MODULE longShort;
  (* LONG and SHORT of the fixed-width SYSTEM.INT8..INT64 and of HUGEINT go by
     byte width (voc's OPT.ShorterOrLongerType): LONG(x) is the narrowest of
     SHORTINT/INTEGER/LONGINT strictly wider than x, else HUGEINT; SHORT(x) the
     widest strictly narrower, else INT8. Which model type that is differs
     between -O2 and -OC, but the values here do not: LONG never changes a
     value, and SHORT keeps its low bits at a width no wider than the source,
     which is the same under both models for every case below.
     semantic-long-short-width pins the result types; this checks the
     conversions actually widen and truncate. *)
  IMPORT SYSTEM, Out;

  VAR
    i8: SYSTEM.INT8; i16: SYSTEM.INT16; i32: SYSTEM.INT32; i64: SYSTEM.INT64;
    h: HUGEINT;

  PROCEDURE Line(name: ARRAY OF CHAR; value: HUGEINT);
  BEGIN
    Out.String(name); Out.String(" = "); Out.Int(value, 0); Out.Ln
  END Line;

BEGIN
  i8 := -100; i16 := -30000; i32 := -2000000000; i64 := MIN(SYSTEM.INT64);
  Line("LONG(i8)", LONG(i8));
  Line("LONG(i16)", LONG(i16));
  Line("LONG(i32)", LONG(i32));
  Line("LONG(i64)", LONG(i64));
  (* the widened value really is wider: no wrap at the source's width *)
  i32 := MAX(SYSTEM.INT32);
  Line("LONG(MAX(INT32)) + 1", LONG(i32) + 1);
  i16 := MAX(SYSTEM.INT16);
  Line("LONG(MAX(INT16)) + 1", LONG(i16) + 1);

  i8 := 100; Line("SHORT(i8)", SHORT(i8));
  i16 := 300; Line("SHORT(i16)", SHORT(i16));
  i16 := -300; Line("SHORT(-300 as INT16)", SHORT(i16));
  i32 := 70000; Line("SHORT(i32)", SHORT(i32));
  i32 := 123; Line("SHORT(123 as INT32)", SHORT(i32));
  i64 := 4294967301; Line("SHORT(i64)", SHORT(i64));
  i64 := -123456; Line("SHORT(-123456 as INT64)", SHORT(i64));
  h := 4294967301; Line("SHORT(h)", SHORT(h));
  h := -5; Line("SHORT(-5 as HUGEINT)", SHORT(h));
  h := 1; Line("LONG(h)", LONG(h))
END longShort.
