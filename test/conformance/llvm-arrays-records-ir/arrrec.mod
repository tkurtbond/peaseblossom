MODULE arrrec;
  (* PLAN.md Phase 8 step 8's dedicated golden-file fixture for fixed-
     size ARRAY/RECORD codegen: element/field read and write via
     getelementptr (a 1D array, a 2D array via the "ARRAY m, n OF T"
     comma sugar, a plain record, a record nested inside another
     record, and an array of records - every combination this step's
     GenerateDesignatorAddress selector-chain walker needs to compose
     correctly), plus whole-value ARRAY/RECORD assignment (a bare
     "load [N x T]"/"store [N x T]" or "load {...}"/"store {...}",
     already generic since step 5's LoadVar/StoreIntoVar needed no
     changes of their own for this). See llvm-arrays-records for the
     same constructs exercised the other way, at runtime through the
     step 6 write(2) FFI (branching on a computed result, since this
     step's FFI still can't print a computed ARRAY OF CHAR value
     directly). This fixture's own final "sum" was independently
     verified during development via the same C-harness linking
     technique step 5/7 already established: sum=312. *)
  TYPE
    Point = RECORD x, y: INTEGER END;
    Vec3 = ARRAY 3 OF INTEGER;
    Grid = ARRAY 2, 3 OF INTEGER;
    Line = RECORD a, b: Point END;
    PointArr = ARRAY 3 OF Point;
  VAR
    v, v2: Vec3;
    g: Grid;
    p, p2: Point;
    ln: Line;
    pa: PointArr;
    sum, i, j: INTEGER;
BEGIN
  v[0] := 10; v[1] := 20; v[2] := 30;
  sum := v[0] + v[1] + v[2];

  v2 := v;
  v2[1] := 99;
  sum := sum + v2[1] + v[1];

  FOR i := 0 TO 1 DO
    FOR j := 0 TO 2 DO
      g[i, j] := i*10 + j
    END
  END;
  sum := sum + g[1, 2];

  p.x := 5; p.y := 7;
  p2 := p;
  p2.x := 100;
  sum := sum + p.x + p2.x;

  ln.a.x := 1; ln.a.y := 2; ln.b.x := 3; ln.b.y := 4;
  sum := sum + ln.a.x + ln.a.y + ln.b.x + ln.b.y;

  FOR i := 0 TO 2 DO
    pa[i].x := i; pa[i].y := i*2
  END;
  sum := sum + pa[2].x + pa[2].y
END arrrec.
