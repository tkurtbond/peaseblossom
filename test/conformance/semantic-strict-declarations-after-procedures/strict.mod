MODULE Strict;
  (* -strict reports each CONST, TYPE or VAR section after a procedure of
     its block (lines 8, 9, 13 and 16), not those before the first (lines
     5, 6 and, inside Q, 11). Without -strict the module is accepted. *)
  CONST a = 1;
  VAR b: INTEGER;
  PROCEDURE P; BEGIN b := a END P;
  CONST c = 2;
  TYPE T = RECORD f: INTEGER END;
  PROCEDURE Q;
    VAR x: INTEGER;
    PROCEDURE R; END R;
    VAR y: INTEGER;
  BEGIN x := 0; y := 0; R
  END Q;
  VAR t: T;
BEGIN P; Q; t.f := c
END Strict.
