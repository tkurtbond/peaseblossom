MODULE VaxLoops;
  (* PLAN.md Phase 15 step 4: WHILE tests at the top, REPEAT at the
     bottom; LOOP jumps back to its start, and EXIT to the end of the
     innermost LOOP, out of any WHILE or IF inside it *)

  VAR i, n: INTEGER; done: BOOLEAN;

BEGIN
  WHILE (i < n) & ~done DO i := i + 1 END;
  REPEAT i := i - 1 UNTIL i <= 0;
  LOOP
    i := i + 1;
    IF i = 10 THEN EXIT END;
    LOOP
      WHILE n > 0 DO
        IF done THEN EXIT END;
        n := n - 1
      END;
      EXIT
    END
  END
END VaxLoops.
