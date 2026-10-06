MODULE VaxBlockMoves;
  (* PLAN.md Phase 15 step 6: MOVC3 and MOVC5 move at most 65535 bytes,
     their length a word, so a longer copy, string or clearing of the
     frame is several, each next one from where the last left R1 and R3;
     more than 64 bytes of locals are cleared by MOVC5 *)

  TYPE Big = ARRAY 70000 OF CHAR;
  VAR x, y: Big; r: RECORD a: ARRAY 100 OF INTEGER END;

  PROCEDURE Medium;
    VAR m: ARRAY 100 OF CHAR;
  BEGIN
    m[0] := "a"
  END Medium;

  PROCEDURE Huge(b: Big);
    VAR l: Big;
  BEGIN
    l := b;
    l := "abc"
  END Huge;

BEGIN
  x := y;
  Huge(x)
END VaxBlockMoves.
