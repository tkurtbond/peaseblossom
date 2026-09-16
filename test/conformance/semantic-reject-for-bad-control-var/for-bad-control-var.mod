MODULE forBadControlVar;
  (* Oberon2.pdf §9.8: the FOR control variable must be an integer
     variable - x here is REAL. *)

  VAR x: REAL;
BEGIN
  FOR x := 0 TO 10 DO
  END
END forBadControlVar.
