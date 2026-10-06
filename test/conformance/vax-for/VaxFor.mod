MODULE VaxFor;
  (* PLAN.md Phase 15 step 4: FOR as Oberon2.pdf 9.8 says - the control
     variable set to the start, the limit evaluated once, before the loop
     (a variable's value kept in the frame, as the body may change it),
     the test at the top, > for a positive step and < for a negative one,
     and the step added at the bottom *)

  VAR i, n: INTEGER; s: SHORTINT; l: LONGINT;

BEGIN
  FOR i := 0 TO n DO l := l + i END;
  FOR i := 10 TO 1 BY -2 DO l := l - 1 END;
  FOR l := n TO 100000 BY 3 DO END;
  FOR i := s TO s + 5 DO n := n + 1 END
END VaxFor.
