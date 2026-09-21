MODULE arrayassigntrap;
  (* Phase 11 (A21): an open array assigned to a fixed one that has fewer
     elements than it stops the program, exit 9, "open array assigned to an
     array too short for it" - by length alone, even when the string the
     source holds is short (voc traps here too, as an index out of range).
     Cases are chosen by the program's argument; 0 and 1 are the ones that fit,
     2 to 6 do not. *)
  IMPORT Modules, Out;
  TYPE Row = ARRAY 3 OF INTEGER;
  VAR
    which: LONGINT;
    c4: ARRAY 4 OF CHAR; c8: ARRAY 8 OF CHAR;
    i2: ARRAY 2 OF INTEGER; rows: ARRAY 2 OF Row;
    big: ARRAY 3 OF Row; row5: ARRAY 5 OF Row;

  PROCEDURE ToC4(s: ARRAY OF CHAR);
  BEGIN c4 := s; Out.String("copied: "); Out.String(c4); Out.Ln
  END ToC4;

  PROCEDURE ToI2(VAR s: ARRAY OF INTEGER);
  BEGIN i2 := s; Out.String("copied ints"); Out.Ln
  END ToI2;

  PROCEDURE ToRows(VAR s: ARRAY OF Row);
  BEGIN rows := s; Out.String("copied rows"); Out.Ln
  END ToRows;

BEGIN
  Modules.GetIntArg(1, which);
  CASE which OF
    0: ToC4("abc")                       (* 4 elements into 4 *)
  | 1: c8 := "12345"; ToC4("");           (* a short string in a 4-element array: fits *)
       ToI2(i2)
  | 2: ToC4("hello")                     (* 6 into 4 *)
  | 3: c8 := "ab"; c8[2] := 0X; ToC4(c8)  (* 8 into 4, though it holds only "ab" *)
  | 4: ToI2(big[0])                      (* 3 into 2 *)
  | 5: ToRows(big)                       (* 3 rows into 2 *)
  | 6: ToRows(row5)                      (* 5 rows into 2 *)
  END;
  Out.String("reached the end"); Out.Ln
END arrayassigntrap.
