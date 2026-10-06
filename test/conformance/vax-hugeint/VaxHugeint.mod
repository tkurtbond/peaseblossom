MODULE VaxHugeint;
  (* PLAN.md Phase 15 step 3: HUGEINT is a quadword, low longword first
     (the design's section 4). The VAX has no quadword add, subtract or
     compare: + and - are ADDL2/ADWC and SUBL2/SBWC, a comparison the high
     longwords signed and then the low ones unsigned. A narrower integer is
     widened by its sign, ASHL #-31. *)

  VAR i: INTEGER; l: LONGINT; h, g: HUGEINT; b: BOOLEAN;

BEGIN
  h := i;
  h := l;
  h := h + g;
  h := g - h;
  h := h + l;
  h := -h;
  b := h < g;
  b := h = g;
  b := h >= 0
END VaxHugeint.
