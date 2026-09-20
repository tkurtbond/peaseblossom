MODULE constQuotientOverflow;
  (* MIN(HUGEINT) DIV (-1) is 2^63, one past HUGEINT's maximum. Not
     cross-checked against voc: its compiler dies of a floating-point
     exception (SIGFPE) folding it, which poc reports as an ordinary
     error instead. MIN(HUGEINT) MOD (-1) is 0 and fine. *)

  CONST
    tooBig = MIN(HUGEINT) DIV (-1);
    zero = MIN(HUGEINT) MOD (-1);

  VAR
    h: HUGEINT;

BEGIN
  h := tooBig;
  h := zero
END constQuotientOverflow.
