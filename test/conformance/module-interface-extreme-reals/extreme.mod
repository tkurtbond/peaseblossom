MODULE extreme;
  (* Phase 11 step 2 (inventory A2): a computed REAL/LONGREAL constant of any
     magnitude exports. Each of these used to fail with "failed to find a
     round-trip-safe text representation" (the first two, extreme magnitude)
     or come out a few units in the last place off (sub was 1.3D-323). The
     text printed is the shortest digits that ConstantEvaluator.ParseReal,
     now correctly rounded, reads back to the very value; test.sh also reads
     the .sym back as source and requires the second .sym to be identical. *)
  CONST
    half* = MAX(LONGREAL) / 2.0D0;
    big* = 1.0D300 * 1.5D0;
    tiny* = 1.0D-300 / 3.0D0;
    third* = 1.0D0 / 3.0D0;
    twoThirds* = 2.0D0 / 3.0D0;
    tenth* = 1.0D0 / 10.0D0;
    sub* = 4.9406564584124654D-324 * 3.0D0;
    smallest* = 4.9406564584124654D-324 * 1.0D0;
    largestNormalBelow* = 2.2250738585072014D-308 * 1.0D0;
    sum* = 0.1D0 + 0.2D0;
    negative* = -(1.0D0 / 7.0D0);
    exact* = 3.0D0 * 0.25D0;
    single* = 1.0E0 / 3.0E0;
    singleBig* = 1.0E30 * 3.0E0;
    huge* = 1.0D307 * 9.0D0;
END extreme.
