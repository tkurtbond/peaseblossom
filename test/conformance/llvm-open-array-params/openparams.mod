MODULE openparams;
  (* PLAN.md Phase 9 step 7: open-array formal parameters. An Oberon
     procedure takes the array's address and, right after it, one hidden
     length per open dimension, so LEN, indexing (range-checked against the
     run-time length) and passing the array on all work inside it. Covered:
     VAR and value parameters, forwarding between procedures, a value
     parameter being the callee's own copy, one- and two-dimensional arrays
     handed a fixed array or a row of one, ARRAY OF CHAR given a string, a
     COPY into an open array, comparison, records as elements, recursion,
     a type-bound procedure, and an open array passed on to an external C
     procedure (which gets the bare address). Each check prints "FAIL nn "
     on failure; the run ends with "OK". *)
  TYPE
    Point = RECORD x, y: INTEGER END;
    Counter = POINTER TO CounterDesc;
    CounterDesc = RECORD total: INTEGER END;
  VAR
    fixed: ARRAY 5 OF INTEGER;
    grid: ARRAY 3 OF ARRAY 4 OF INTEGER;
    text: ARRAY 12 OF CHAR;
    points: ARRAY 3 OF Point;
    counter: Counter;
    i, j: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR msg: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      msg[0] := "F"; msg[1] := "A"; msg[2] := "I"; msg[3] := "L"; msg[4] := " ";
      msg[5] := CHR(ORD("0") + number DIV 10); msg[6] := CHR(ORD("0") + number MOD 10);
      msg[7] := " "; msg[8] := 0X;
      SysWrite(1, msg, 8)
    END
  END Check;

  PROCEDURE Sum(VAR a: ARRAY OF INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO total := total + a[k] END;
    RETURN total
  END Sum;

  PROCEDURE Fill(VAR a: ARRAY OF INTEGER; base: INTEGER);
    VAR k: INTEGER;
  BEGIN
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO a[k] := base + k END
  END Fill;

  (* the same open array handed on, twice *)
  PROCEDURE FillAndSum(VAR a: ARRAY OF INTEGER): INTEGER;
  BEGIN
    Fill(a, 10);
    RETURN Sum(a)
  END FillAndSum;

  (* a value parameter is a copy: the caller's array is untouched *)
  PROCEDURE ScribbleOnCopy(a: ARRAY OF INTEGER): INTEGER;
  BEGIN
    a[0] := 1000;
    RETURN Sum(a)
  END ScribbleOnCopy;

  PROCEDURE Shape(VAR a: ARRAY OF ARRAY OF INTEGER): LONGINT;
  BEGIN RETURN LEN(a, 0) * 100 + LEN(a, 1) END Shape;

  PROCEDURE Trace(VAR a: ARRAY OF ARRAY OF INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a, 0)) - 1 DO total := total + a[k, k] END;
    RETURN total
  END Trace;

  (* one row of a two-dimensional open array, passed on as an open array *)
  PROCEDURE RowSum(VAR a: ARRAY OF ARRAY OF INTEGER; row: INTEGER): INTEGER;
  BEGIN RETURN Sum(a[row]) END RowSum;

  PROCEDURE StringLength(s: ARRAY OF CHAR): LONGINT;
  BEGIN RETURN LEN(s) END StringLength;

  PROCEDURE IsHello(s: ARRAY OF CHAR): BOOLEAN;
  BEGIN RETURN s = "hello" END IsHello;

  PROCEDURE Fetch(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
  BEGIN COPY(src, dst) END Fetch;

  PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k
  END Length;

  (* an open array of records, and through it a field of one *)
  PROCEDURE SumPoints(VAR a: ARRAY OF Point): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO total := total + a[k].x * 10 + a[k].y END;
    RETURN total
  END SumPoints;

  PROCEDURE Recursive(VAR a: ARRAY OF INTEGER; from: INTEGER): INTEGER;
  BEGIN
    IF from >= SHORT(LEN(a)) THEN RETURN 0 END;
    RETURN a[from] + Recursive(a, from + 1)
  END Recursive;

  (* an open array given to an external C procedure: the bare address *)
  PROCEDURE Emit(s: ARRAY OF CHAR);
  BEGIN SysWrite(1, s, Length(s)) END Emit;

  PROCEDURE (c: Counter) AddAll(VAR a: ARRAY OF INTEGER);
  BEGIN c.total := c.total + Sum(a) END AddAll;

BEGIN
  Fill(fixed, 1);
  Check(1, Sum(fixed) = 15);
  Check(2, FillAndSum(fixed) = 60);
  Check(3, fixed[4] = 14);
  Check(4, ScribbleOnCopy(fixed) = 60 - 10 + 1000);
  Check(5, fixed[0] = 10);
  FOR i := 0 TO 2 DO FOR j := 0 TO 3 DO grid[i][j] := i * 10 + j END END;
  Check(6, Shape(grid) = 304);
  Check(7, Trace(grid) = 0 + 11 + 22);
  Check(8, RowSum(grid, 2) = 20 + 21 + 22 + 23);
  Check(9, Sum(grid[1]) = 10 + 11 + 12 + 13);
  Check(10, StringLength("abc") = 4);
  text := "hello";
  Check(11, StringLength(text) = 12);
  Check(12, IsHello(text));
  Check(13, IsHello("hello"));
  Check(14, ~IsHello("hellp"));
  Fetch(text, "world");
  Check(15, text = "world");
  Fetch(text, "a long string beyond the room");
  Check(16, text = "a long stri");
  Check(17, Length(text) = 11);
  FOR i := 0 TO 2 DO points[i].x := i + 1; points[i].y := i END;
  Check(18, SumPoints(points) = (10 + 0) + (20 + 1) + (30 + 2));
  Check(19, Recursive(fixed, 0) = 60);
  NEW(counter);
  counter.total := 0;
  counter.AddAll(fixed);
  counter.AddAll(grid[0]);
  Check(20, counter.total = 60 + 0 + 1 + 2 + 3);
  Emit("[emitted]");
  SysWrite(1, "OK", 2)
END openparams.
