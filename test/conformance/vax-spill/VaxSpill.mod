MODULE VaxSpill;
  (* PLAN.md Phase 15 step 3: an expression needing more than R0-R5 (the
     design's section 7) spills the oldest register in use to a longword
     below FP - a HUGEINT's pair to two - and uses it from there; the
     initializer then saves the R2-R5 it writes, and makes room for the
     slots with SUBL2 #n, SP, which RET gives back *)

  VAR a: LONGINT; h, g: HUGEINT;

BEGIN
  a := (a + 1) * ((a + 2) * ((a + 3) * ((a + 4) * ((a + 5) * ((a + 6) * ((a + 7) * ((a + 8) * (a + 9))))))));
  h := (h + g) - ((h - g) + ((g - h) - ((h + g) - (g + h))))
END VaxSpill.
