MODULE VaxIf;
  (* PLAN.md Phase 15 step 4: IF and ELSIF test their conditions by
     jumping, without making a BOOLEAN value: a relation by a byte branch
     over JMP L^ (the design's section 3), & and OR by jumping past the
     rest, ~ by testing the other way; a BOOLEAN variable by its low bit *)

  VAR i, j: INTEGER; p, q: BOOLEAN; c: CHAR;

BEGIN
  IF i < j THEN i := 1 END;
  IF p THEN i := 2 ELSE i := 3 END;
  IF (i = j) & p OR ~q THEN
    i := 4
  ELSIF c >= "a" THEN
    i := 5
  ELSIF ~(p OR q) THEN
    i := 6
  ELSE
    i := 7
  END
END VaxIf.
