MODULE forFinalValue;
  (* The FOR final value must be assignment compatible with the control
     variable, as in voc (err 113) - stricter than Oberon2.pdf 9.8, which
     asks only that it be comparable (doc/language-extensions.md, "FOR
     final value"). Lines 13-15 are errors; 16-19 are not. *)

  VAR
    i: SHORTINT; k: INTEGER; n: INTEGER; s: SHORTINT; r: REAL;
BEGIN
  n := 300; s := 5; r := 3.5;
  (* rejected: a wider integer variable, a REAL, a constant that needs
     INTEGER *)
  FOR i := 0 TO n DO END;
  FOR k := 0 TO r DO END;
  FOR i := 0 TO 300 DO END;
  FOR k := 0 TO s DO END;
  FOR k := 0 TO n BY -1 DO END;
  FOR i := 0 TO 100 DO END;
  FOR i := s TO s + 1 DO END
END forFinalValue.
