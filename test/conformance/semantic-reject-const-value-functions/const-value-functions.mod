MODULE constValueFunctions;
  (* Phase 11 step 2 (inventory A1): what a constant ORD/ABS/CHR/CAP/ENTIER/
     LONG/SHORT/ODD call is rejected for. Each is voc's error too (203 "number
     too large", 220 "illegal value of parameter", 111 "operand inapplicable")
     except the two marked poc, where poc keeps to the report. *)
  CONST
    ordString = ORD("AB");
    ordBoolean = ORD(TRUE);
    chrHigh = CHR(256);
    chrNegative = CHR(-1);
    capString = CAP("AB");
    absSet = ABS({1});
    absMin = ABS(MIN(HUGEINT));
    entierBig = ENTIER(1.0D19);
    entierInteger = ENTIER(5);
    shortWide = SHORT(500);
    shortReal = SHORT(1.0D300);
    longLong = LONG(2.5D0);       (* poc: the report's LONG takes no LONGREAL *)
    oddReal = ODD(2.5);
    twoArguments = ABS(1, 2);
END constValueFunctions.
