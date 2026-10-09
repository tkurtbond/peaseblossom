MODULE VaxCopyLong;
  (* PLAN.md Phase 15 step 7b: COPY(x, v) with x or v longer than 65535
     characters, the most one LOCC or MOVC5 takes (the design's section
     8): the 0X found by LOCC in pieces, then the characters moved by
     MOVC3 in pieces, then 0X. *)

  TYPE Big = ARRAY 70010 OF CHAR;

  VAR big: ARRAY 70000 OF CHAR; bigger: Big; mid: ARRAY 66000 OF CHAR; small: ARRAY 10 OF CHAR;

  (* big's first n characters "A", then 0X; every other array all "Z" *)
  PROCEDURE Fill(n: LONGINT);
    VAR i: LONGINT;
  BEGIN
    FOR i := 0 TO n - 1 DO big[i] := "A" END;
    IF n < LEN(big) THEN big[n] := 0X END;
    FOR i := 0 TO LEN(bigger) - 1 DO bigger[i] := "Z" END;
    FOR i := 0 TO LEN(mid) - 1 DO mid[i] := "Z" END;
    FOR i := 0 TO LEN(small) - 1 DO small[i] := "Z" END
  END Fill;

  PROCEDURE CopyBigger;
  BEGIN COPY(big, bigger)
  END CopyBigger;

  PROCEDURE CopyMid;
  BEGIN COPY(big, mid)
  END CopyMid;

  PROCEDURE CopySmall;
  BEGIN COPY(big, small)
  END CopySmall;

  PROCEDURE CopyTo(VAR v: Big);
  BEGIN COPY(big, v)
  END CopyTo;

  PROCEDURE CopyConstant;
  BEGIN COPY("hello", bigger)
  END CopyConstant;

END VaxCopyLong.
