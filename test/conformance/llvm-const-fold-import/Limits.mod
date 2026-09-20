MODULE Limits;
  (* The constants of llvm-const-fold, exported: an importer sees each one
     through a .sym file, as its value - a folded integer is re-typed by
     that value, and MAX/MIN of the real types come back as themselves. *)
  CONST
    total* = 2 * 100 + 2 * 10;
    negShort* = -128;
    beyondShort* = MAX(SHORTINT) + 1;
    million* = 1000 * 1000;
    wide* = 100000 * 100000;
    shifted* = ASH(1, 20);
    hugeShift* = ASH(1, 40);
    bigReal* = MAX(REAL);
    lowReal* = MIN(REAL);
    bigLongReal* = MAX(LONGREAL);
    lowLongReal* = MIN(LONGREAL);
END Limits.
