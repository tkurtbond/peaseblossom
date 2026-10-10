MODULE VaxRealRange;
  (* Phase 16 step 3 (the design's section 14, item 9): a real constant
     beyond the largest value of the VAX's format, F_floating's for a REAL,
     G_floating's for a LONGREAL, is an error at its position, as it would
     be to MACRO. MAX(LONGREAL) and MIN(REAL), which the front end folds to
     IEEE 754's largest values, are the VAX format's largest, and no error,
     nor is a value too small for the format, which is 0. *)
  VAR r: REAL; x: LONGREAL;
BEGIN
  x := 1.0D308; r := -2.0E38;
  x := MAX(LONGREAL); r := MIN(REAL); x := 1.0D-320
END VaxRealRange.
