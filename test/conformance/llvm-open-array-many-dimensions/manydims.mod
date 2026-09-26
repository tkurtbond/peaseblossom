MODULE manydims;
  (* Open arrays with more than 8 open dimensions (Phase 11 A17: poc's
     limit was 8 until its backend's lengths became a list). Nine and
     twenty open dimensions go through every path that carries lengths: a
     VAR and a value parameter, LEN at each level, NEW and the heap block's
     header, a row of a heap array and of a fixed array passed on, a nested
     procedure using its enclosing procedure's open array, and a value
     parameter's copy staying apart from the original; sixty-four make a
     call's argument text outgrow the 800 characters poc used to build it
     in. Every array is 2 by 1 by ... by 1 by 3, and the element at the
     far corner is the one looked at. voc accepts all of it, and test.sh
     compares under -O2 and -OC up to the "nested" lines, which come last:
     for an open array of two or more dimensions voc gives a nested
     procedure garbage inner lengths, and with nine it stops. (No row of an
     open-array *parameter* is passed on either: voc gets that wrong too.
     doc/voc-bugs/README.md has both.) *)
  IMPORT Out;

  TYPE
    Nine = ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER;
    PointerToNine = POINTER TO ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER;
    PointerToTwenty = POINTER TO ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF CHAR;
    PointerToSixtyFour = POINTER TO ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF CHAR;

  VAR
    fixed: ARRAY 2, 1, 1, 1, 1, 1, 1, 1, 3 OF INTEGER;
    p: PointerToNine;
    q: PointerToTwenty;
    r: PointerToSixtyFour;
    k: INTEGER;

  (* LEN's dimension must be a constant, so one call per level *)
  PROCEDURE Lengths(VAR a: Nine);
  BEGIN
    Out.String("lengths");
    Out.Char(" "); Out.Int(LEN(a, 0), 0);
    Out.Char(" "); Out.Int(LEN(a, 1), 0);
    Out.Char(" "); Out.Int(LEN(a, 2), 0);
    Out.Char(" "); Out.Int(LEN(a, 3), 0);
    Out.Char(" "); Out.Int(LEN(a, 4), 0);
    Out.Char(" "); Out.Int(LEN(a, 5), 0);
    Out.Char(" "); Out.Int(LEN(a, 6), 0);
    Out.Char(" "); Out.Int(LEN(a, 7), 0);
    Out.Char(" "); Out.Int(LEN(a, 8), 0);
    Out.Ln
  END Lengths;

  (* a value parameter: the callee's own copy *)
  PROCEDURE Corner(a: Nine): INTEGER;
  BEGIN
    RETURN a[1, 0, 0, 0, 0, 0, 0, 0, 2]
  END Corner;

  PROCEDURE SetCorner(VAR a: Nine; x: INTEGER);
  BEGIN
    a[1, 0, 0, 0, 0, 0, 0, 0, 2] := x
  END SetCorner;

  (* changes its copy only *)
  PROCEDURE ChangeCopy(a: Nine): INTEGER;
  BEGIN
    a[1, 0, 0, 0, 0, 0, 0, 0, 2] := -1;
    RETURN a[1, 0, 0, 0, 0, 0, 0, 0, 2]
  END ChangeCopy;

  PROCEDURE Nested(VAR a: Nine): INTEGER;
    PROCEDURE Inner(): INTEGER;
    BEGIN
      RETURN a[1, 0, 0, 0, 0, 0, 0, 0, 2] + SHORT(LEN(a, 8))
    END Inner;
  BEGIN
    RETURN Inner()
  END Nested;

  (* eight open dimensions: a row of a nine-dimensional array *)
  PROCEDURE RowCorner(VAR r: ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER): INTEGER;
  BEGIN
    RETURN r[0, 0, 0, 0, 0, 0, 0, 2] + SHORT(LEN(r, 7))
  END RowCorner;

  PROCEDURE Twenty(VAR a: ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF CHAR);
  BEGIN
    Out.String("twenty "); Out.Int(LEN(a, 0), 0); Out.Char(" "); Out.Int(LEN(a, 19), 0);
    Out.Char(" "); Out.Char(a[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]); Out.Ln
  END Twenty;

  (* 64 lengths make a call's argument text longer than the fixed 800
     characters poc used to build it in *)
  PROCEDURE SixtyFour(VAR a: ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF CHAR);
  BEGIN
    Out.String("sixty-four "); Out.Int(LEN(a, 0), 0); Out.Char(" "); Out.Int(LEN(a, 63), 0);
    Out.Char(" "); Out.Char(a[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]); Out.Ln
  END SixtyFour;

  PROCEDURE TwentyCopy(a: ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF CHAR): CHAR;
  BEGIN
    a[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2] := "?";
    RETURN a[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]
  END TwentyCopy;

BEGIN
  fixed[1, 0, 0, 0, 0, 0, 0, 0, 2] := 7;
  Lengths(fixed);
  Out.String("fixed corner "); Out.Int(Corner(fixed), 0); Out.Ln;
  SetCorner(fixed, 8);
  Out.String("after SetCorner "); Out.Int(fixed[1, 0, 0, 0, 0, 0, 0, 0, 2], 0); Out.Ln;
  Out.String("copy changed to "); Out.Int(ChangeCopy(fixed), 0);
  Out.String(", original "); Out.Int(fixed[1, 0, 0, 0, 0, 0, 0, 0, 2], 0); Out.Ln;
  Out.String("fixed row "); Out.Int(RowCorner(fixed[1]), 0); Out.Ln;

  NEW(p, 2, 1, 1, 1, 1, 1, 1, 1, 3);
  p[1, 0, 0, 0, 0, 0, 0, 0, 2] := 70;
  Lengths(p^);
  Out.String("heap corner "); Out.Int(Corner(p^), 0); Out.Ln;
  SetCorner(p^, 80);
  Out.String("after SetCorner "); Out.Int(p[1, 0, 0, 0, 0, 0, 0, 0, 2], 0); Out.Ln;
  Out.String("heap row "); Out.Int(RowCorner(p[1]), 0); Out.Ln;
  Out.String("LEN(p^, 8) "); Out.Int(LEN(p^, 8), 0); Out.Ln;

  k := 1;
  NEW(q, 2, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, 3);
  q[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2] := "z";
  Twenty(q^);
  Out.String("twenty copy "); Out.Char(TwentyCopy(q^));
  Out.String(", original "); Out.Char(q[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]); Out.Ln;

  NEW(r, 2, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, 3);
  r[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2] := "w";
  SixtyFour(r^);

  (* last, since voc stops here (doc/voc-bugs/README.md) *)
  Out.String("nested "); Out.Int(Nested(fixed), 0); Out.Ln;
  Out.String("nested "); Out.Int(Nested(p^), 0); Out.Ln
END manydims.
