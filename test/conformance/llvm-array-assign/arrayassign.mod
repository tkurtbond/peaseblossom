MODULE arrayassign;
  (* voc's array assignment, beyond Oberon2.pdf (Phase 11, A21;
     doc/array-assignment-survey.md): v := e for a fixed array v and an array
     e of the same element type that is a fixed array no longer than v, or an
     open array no longer than v at run time.  All of e is copied, by size and
     whatever it holds; the rest of v is left as it was.  Both compilers
     accept and do the same, so test.sh runs this under voc and poc and both
     size models and requires the same output. *)
  IMPORT Out;

  TYPE
    Row = ARRAY 3 OF INTEGER;
    R = RECORD tag: INTEGER; a: ARRAY 6 OF CHAR; after: INTEGER END;

  VAR
    i8: ARRAY 8 OF INTEGER; i3, i3b: ARRAY 3 OF INTEGER; i4: ARRAY 4 OF INTEGER;
    c4: ARRAY 4 OF CHAR; c8: ARRAY 8 OF CHAR;
    rows2: ARRAY 2 OF Row; rows3: ARRAY 3 OF Row;
    grid: ARRAY 3 OF ARRAY 4 OF INTEGER;
    rec: R;

  PROCEDURE ShowInts(label: ARRAY OF CHAR; VAR a: ARRAY OF INTEGER);
    VAR k: INTEGER;
  BEGIN
    Out.String(label);
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO Out.Char(" "); Out.Int(a[k], 0) END;
    Out.Ln
  END ShowInts;

  PROCEDURE ShowChars(label: ARRAY OF CHAR; VAR a: ARRAY OF CHAR);
    VAR k: INTEGER;
  BEGIN
    Out.String(label); Out.Char(" ");
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO
      IF a[k] = 0X THEN Out.Char("~") ELSE Out.Char(a[k]) END
    END;
    Out.Ln
  END ShowChars;

  PROCEDURE Fill(VAR a: ARRAY OF INTEGER; v: INTEGER);
    VAR k: INTEGER;
  BEGIN
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO a[k] := v END
  END Fill;

  (* an open array, as a value parameter and as a VAR one, into fixed arrays *)
  PROCEDURE FromOpenVar(VAR s: ARRAY OF INTEGER);
  BEGIN
    i8 := s
  END FromOpenVar;

  PROCEDURE FromOpenValue(s: ARRAY OF CHAR);
  BEGIN
    c8 := s
  END FromOpenValue;

  PROCEDURE IntoRecord(VAR s: ARRAY OF CHAR);
  BEGIN
    rec.a := s
  END IntoRecord;

  PROCEDURE FromRows(VAR s: ARRAY OF Row);
  BEGIN
    rows3 := s
  END FromRows;

  PROCEDURE Local(VAR s: ARRAY OF INTEGER);
    VAR mine: ARRAY 5 OF INTEGER;
  BEGIN
    Fill(mine, 9); mine := s; ShowInts("local", mine)
  END Local;

BEGIN
  (* a shorter fixed array into a longer one: the tail stays *)
  Fill(i8, 7); i3[0] := 1; i3[1] := 2; i3[2] := 3;
  i8 := i3; ShowInts("shorter fixed", i8);
  (* the same length, though declared apart (voc treats these as the same
     type only structurally; here they are two types and the rule copies) *)
  i3b[0] := 4; i3b[1] := 5; i3b[2] := 6;
  i3 := i3b; ShowInts("same length", i3);
  (* an element of an array, and an array inside a record *)
  Fill(grid[1], 0); grid[1] := i3b; ShowInts("row of a grid", grid[1]);
  i4[0] := 1; i4[1] := 2; i4[2] := 3; i4[3] := 4;
  grid[2] := i4; ShowInts("grid row 2", grid[2]);
  (* characters: the whole array is copied, a terminator in the middle and all *)
  c4[0] := "a"; c4[1] := "b"; c4[2] := 0X; c4[3] := "d";
  c8 := "1234567"; c8 := c4; ShowChars("chars", c8);
  (* named element type *)
  rows2[0][0] := 1; rows2[0][1] := 2; rows2[0][2] := 3;
  rows2[1][0] := 4; rows2[1][1] := 5; rows2[1][2] := 6;
  Fill(rows3[0], 0); Fill(rows3[1], 0); Fill(rows3[2], 8);
  rows3 := rows2; ShowInts("row 0", rows3[0]); ShowInts("row 1", rows3[1]); ShowInts("row 2", rows3[2]);
  (* an open source: as long as, or shorter than, the target *)
  Fill(i8, 0); FromOpenVar(i8);
  Fill(i8, 5); FromOpenVar(i3); ShowInts("open var", i8);
  c8 := "abcdefg"; FromOpenValue("xyz"); ShowChars("open value", c8);
  rec.tag := 1; rec.after := 2; rec.a := "qrstu"; IntoRecord(c4); ShowChars("record", rec.a);
  Out.Int(rec.tag, 0); Out.Char(" "); Out.Int(rec.after, 0); Out.Ln;
  Fill(rows3[0], 0); Fill(rows3[1], 0); Fill(rows3[2], 8);
  FromRows(rows2); ShowInts("open rows 0", rows3[0]); ShowInts("open rows 2", rows3[2]);
  Local(i3); Local(i4)
END arrayassign.
