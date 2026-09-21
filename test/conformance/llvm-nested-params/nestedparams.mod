MODULE nestedparams;
  (* Phase 11 step 8, steps 3-4 (doc/nested-procedures.md): the variables of an
     enclosing procedure that are not plain locals - what a nested procedure
     must be handed besides an address. A VAR parameter (its actual argument's
     own address); a VAR parameter of record type, which travels with the
     run-time type tag of what was passed (IS, WITH and passing it on as a VAR
     argument must see the dynamic type); an open array, value and VAR, one and
     two dimensional, with its run-time lengths (LEN, indexing checked against
     them, passing it on as an open array argument); a VAR receiver (its tag
     too, so a bound procedure is dispatched on the real type); a pointer
     receiver; a value parameter of pointer type assigned inside the nested
     procedure; WITH in a nested procedure over an enclosing pointer. "NN ok"
     or "NN BAD" per check. *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD kind: INTEGER END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc) radius: INTEGER END;
    Counter = RECORD n: INTEGER END;
    Matrix = ARRAY 2, 3 OF INTEGER;
  VAR grown: INTEGER;

  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Report(number: INTEGER; ok: BOOLEAN);
    VAR line: ARRAY 12 OF CHAR;
  BEGIN
    line[0] := CHR(ORD("0") + number DIV 10); line[1] := CHR(ORD("0") + number MOD 10); line[2] := " ";
    IF ok THEN
      line[3] := "o"; line[4] := "k"; line[5] := 0AX; SysWrite(1, line, 6)
    ELSE
      line[3] := "B"; line[4] := "A"; line[5] := "D"; line[6] := 0AX; SysWrite(1, line, 7)
    END
  END Report;

  (* what a nested procedure passes an enclosing VAR record on to *)
  PROCEDURE Kind(VAR r: ShapeDesc): INTEGER;
  BEGIN
    IF r IS CircleDesc THEN RETURN 2 ELSE RETURN 1 END
  END Kind;

  PROCEDURE SumOf(VAR a: ARRAY OF INTEGER): INTEGER;
    VAR i, t: INTEGER;
  BEGIN
    t := 0;
    FOR i := 0 TO SHORT(LEN(a)) - 1 DO t := t + a[i] END;
    RETURN t
  END SumOf;

  PROCEDURE (VAR c: Counter) Add(k: INTEGER);
  BEGIN c.n := c.n + k
  END Add;

  PROCEDURE (VAR c: Counter) Twice;
    PROCEDURE Again;
    BEGIN c.Add(2)
    END Again;
  BEGIN
    Again; Again
  END Twice;

  PROCEDURE (VAR c: Counter) Bump;
    PROCEDURE Step;
    BEGIN c.n := c.n + 1
    END Step;
  BEGIN
    Step; Step
  END Bump;

  PROCEDURE (s: Shape) Grow;
    VAR other: Shape;
    PROCEDURE Reset;
    BEGIN s.kind := 50
    END Reset;
    PROCEDURE Replace;
    BEGIN s := other
    END Replace;
  BEGIN
    NEW(other); other.kind := 77;
    Reset; Replace;
    grown := s.kind
  END Grow;

  PROCEDURE ByVar(VAR x: INTEGER);
    PROCEDURE Inc1;
    BEGIN x := x + 1
    END Inc1;
  BEGIN
    Inc1; Inc1
  END ByVar;

  PROCEDURE ByRecord(VAR sd: ShapeDesc; VAR seen, radius: INTEGER);
    PROCEDURE Test;
    BEGIN
      IF sd IS CircleDesc THEN seen := 2 ELSE seen := 1 END;
      WITH sd: CircleDesc DO radius := sd.radius ELSE radius := -1 END
    END Test;
    PROCEDURE Forward(): INTEGER;
    BEGIN RETURN Kind(sd)
    END Forward;
  BEGIN
    Test;
    IF Forward() # seen THEN seen := 99 END
  END ByRecord;

  PROCEDURE ByOpenVar(VAR a: ARRAY OF INTEGER; VAR total, length: INTEGER);
    PROCEDURE Fill;
      VAR i: INTEGER;
    BEGIN
      FOR i := 0 TO SHORT(LEN(a)) - 1 DO a[i] := (i + 1) * 10 END
    END Fill;
    PROCEDURE Measure;
    BEGIN total := SumOf(a); length := SHORT(LEN(a))
    END Measure;
  BEGIN
    Fill; Measure
  END ByOpenVar;

  PROCEDURE ByOpenValue(a: ARRAY OF CHAR; VAR length, first: INTEGER);
    PROCEDURE Measure;
    BEGIN length := SHORT(LEN(a)); first := ORD(a[0])
    END Measure;
    PROCEDURE Scribble;
    BEGIN a[0] := "Z"
    END Scribble;
  BEGIN
    Scribble; Measure
  END ByOpenValue;

  PROCEDURE ByMatrix(VAR m: ARRAY OF ARRAY OF INTEGER; VAR rows, columns, corner: INTEGER);
    PROCEDURE Measure;
    BEGIN
      rows := SHORT(LEN(m, 0)); columns := SHORT(LEN(m, 1));
      corner := m[LEN(m, 0) - 1, LEN(m, 1) - 1]
    END Measure;
  BEGIN
    Measure
  END ByMatrix;

  PROCEDURE ByWith(s: Shape; VAR radius: INTEGER);
    PROCEDURE Radius;
    BEGIN
      WITH s: Circle DO radius := s.radius ELSE radius := -1 END
    END Radius;
  BEGIN
    Radius
  END ByWith;

  PROCEDURE Main;
    VAR
      x, seen, radius, total, length, first, rows, columns, corner: INTEGER;
      plain: ShapeDesc; round: CircleDesc; c: Counter; sh: Shape; ci: Circle;
      v: ARRAY 4 OF INTEGER; str: ARRAY 6 OF CHAR; m: Matrix;
  BEGIN
    x := 5; ByVar(x); Report(1, x = 7);
    plain.kind := 0; ByRecord(plain, seen, radius); Report(2, (seen = 1) & (radius = -1));
    round.radius := 9; ByRecord(round, seen, radius); Report(3, (seen = 2) & (radius = 9));
    ByOpenVar(v, total, length); Report(4, (total = 100) & (length = 4) & (v[3] = 40));
    str := "abcde"; ByOpenValue(str, length, first); Report(5, (length = 6) & (first = ORD("Z")) & (str[0] = "a"));
    m[0, 0] := 1; m[1, 2] := 6; ByMatrix(m, rows, columns, corner); Report(6, (rows = 2) & (columns = 3) & (corner = 6));
    c.n := 0; c.Bump; Report(7, c.n = 2);
    c.Twice; Report(8, c.n = 6);
    NEW(sh); sh.kind := 1; grown := 0; sh.Grow; Report(9, (sh.kind = 50) & (grown = 77));
    NEW(ci); ci.radius := 4; ByWith(ci, radius); Report(10, radius = 4);
    NEW(sh); ByWith(sh, radius); Report(11, radius = -1)
  END Main;

BEGIN
  Main
END nestedparams.
