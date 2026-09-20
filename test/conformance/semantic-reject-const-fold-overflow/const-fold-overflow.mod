MODULE constFoldOverflow;
  (* A constant integer expression is folded in 64 bits, HUGEINT's range,
     and an operation whose value does not fit is an error, where it used
     to wrap silently: voc's ConstOp reports each of these (errors 203-208:
     "number too large", "product too large", "sum too large", "difference
     too large", "division by zero", "overflow in arithmetic shift"), each
     probed against real voc 2026-09-19. The same expressions in ordinary
     statements are folded and reported too. A constant ASH is only
     defined for counts -62..62 (voc's maxExp), and for a left shift whose
     result fits: ASH(3, 62) does not. *)

  CONST
    tooBigSum = MAX(HUGEINT) + 1;
    tooSmallDifference = MIN(HUGEINT) - 1;
    tooBigProduct = 4000000000 * 4000000000;
    tooBigNegation = -MIN(HUGEINT);
    divideByZero = 5 DIV 0;
    moduloZero = 5 MOD 0;
    countTooBig = ASH(1, 63);
    countTooSmall = ASH(1000, -63);
    shiftOverflows = ASH(3, 62);
    edgeIsFine = ASH(1, 62);
    smallestIsFine = ASH(1000, -62);

  VAR
    i: INTEGER; h: HUGEINT;

BEGIN
  h := MAX(HUGEINT) + 1;
  h := MIN(HUGEINT) - 1;
  h := 4000000000 * 4000000000;
  h := -MIN(HUGEINT);
  i := 5 DIV 0;
  i := 5 MOD 0;
  h := ASH(MAX(HUGEINT), 1);
  h := ASH(1, 63)
END constFoldOverflow.
