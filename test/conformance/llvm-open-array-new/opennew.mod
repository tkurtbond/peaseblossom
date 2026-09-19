MODULE opennew;
  (* PLAN.md Phase 9 step 7: pointers to open arrays and NEW(p, n0, ...,
     nk-1). The block holds the lengths (one word per open dimension) and
     then the elements; p[i], p[i, j], p^ and LEN(p^, d) work on it, p^ can
     be passed to an open-array parameter, and an array of pointers, of
     records, or of characters is fine. The last part runs the collector
     over many pointer-holding arrays, to show the descriptor tells it to
     trace the elements past the lengths. Each check prints "FAIL nn " on
     failure; the run ends with "OK". *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: INTEGER; next: Node END;
    Nodes = POINTER TO ARRAY OF Node;
    Point = RECORD x, y: INTEGER END;
    Points = POINTER TO ARRAY OF Point;
    Vector = POINTER TO ARRAY OF INTEGER;
    Matrix = POINTER TO ARRAY OF ARRAY OF INTEGER;
    Triple = ARRAY 3 OF INTEGER;
    Rows = POINTER TO ARRAY OF Triple;
    Cube = POINTER TO ARRAY OF ARRAY OF ARRAY OF INTEGER;
    Chars = POINTER TO ARRAY OF CHAR;
    Holder = POINTER TO HolderDesc;
    HolderDesc = RECORD
      items: Nodes;
      name: Chars
    END;
  VAR
    nodes: Nodes; points: Points; rows: Rows; cube: Cube; chars: Chars; holder: Holder;
    vector: Vector; matrix: Matrix; scratch: Node;
    keep: ARRAY 50 OF Nodes;
    i, j, k, alive, round: INTEGER;
    wide: HUGEINT;
    local: ARRAY 6 OF CHAR;
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

  PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k
  END Length;

  PROCEDURE Emit(s: ARRAY OF CHAR);
  BEGIN SysWrite(1, s, Length(s)) END Emit;

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

  PROCEDURE Shape(VAR a: ARRAY OF ARRAY OF INTEGER): LONGINT;
  BEGIN RETURN LEN(a, 0) * 100 + LEN(a, 1) END Shape;

  PROCEDURE Trace(VAR a: ARRAY OF ARRAY OF INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a, 0)) - 1 DO total := total + a[k, k] END;
    RETURN total
  END Trace;

  PROCEDURE ChainLength(a: ARRAY OF Node; at: INTEGER): INTEGER;
    VAR total: INTEGER; p: Node;
  BEGIN
    total := 0; p := a[at];
    WHILE p # NIL DO INC(total); p := p.next END;
    RETURN total
  END ChainLength;

  PROCEDURE SumPoints(VAR a: ARRAY OF Point): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO total := total + a[k].x * 10 + a[k].y END;
    RETURN total
  END SumPoints;

  PROCEDURE RowTotal(VAR a: ARRAY OF Triple): INTEGER;
    VAR r, c, total: INTEGER;
  BEGIN
    total := 0;
    FOR r := 0 TO SHORT(LEN(a, 0)) - 1 DO
      FOR c := 0 TO SHORT(LEN(a, 1)) - 1 DO total := total + a[r][c] END
    END;
    RETURN total
  END RowTotal;

  PROCEDURE CubeCorner(VAR c: ARRAY OF ARRAY OF ARRAY OF INTEGER): INTEGER;
  BEGIN RETURN c[SHORT(LEN(c, 0)) - 1, SHORT(LEN(c, 1)) - 1, SHORT(LEN(c, 2)) - 1] END CubeCorner;

  PROCEDURE Depth(VAR a: ARRAY OF INTEGER; from: INTEGER): INTEGER;
  BEGIN
    IF from >= SHORT(LEN(a)) THEN RETURN 0 END;
    RETURN a[from] + Depth(a, from + 1)
  END Depth;

  PROCEDURE At(VAR a: ARRAY OF INTEGER; index: HUGEINT): INTEGER;
  BEGIN RETURN a[index] END At;

BEGIN
  (* one dimension *)
  NEW(vector, 7);
  Check(1, LEN(vector^) = 7);
  Fill(vector^, 100);
  Check(2, vector[6] = 106);
  Check(3, Sum(vector^) = 721);
  vector[3] := 0;
  Check(4, Sum(vector^) = 721 - 103);
  (* two dimensions *)
  NEW(matrix, 5, 6);
  Check(5, Shape(matrix^) = 506);
  FOR i := 0 TO 4 DO FOR j := 0 TO 5 DO matrix[i, j] := i * 100 + j END END;
  Check(6, matrix[4][5] = 405);
  Check(7, matrix^[3, 2] = 302);
  Check(8, Trace(matrix^) = 0 + 101 + 202 + 303 + 404);
  Check(9, LEN(matrix^, 1) = 6);
  Check(10, LEN(matrix[2]) = 6);
  Check(11, Sum(matrix[4]) = 2415);
  (* three dimensions *)
  NEW(cube, 2, 3, 4);
  Check(12, (LEN(cube^, 0) = 2) & (LEN(cube^, 1) = 3) & (LEN(cube^, 2) = 4));
  FOR i := 0 TO 1 DO FOR j := 0 TO 2 DO FOR k := 0 TO 3 DO cube[i, j, k] := i * 100 + j * 10 + k END END END;
  Check(13, CubeCorner(cube^) = 123);
  Check(14, cube[1][2][3] = 123);
  Check(15, cube[0, 1, 2] = 12);
  (* an open outer dimension over a fixed element *)
  NEW(rows, 4);
  FOR i := 0 TO 3 DO FOR j := 0 TO 2 DO rows[i][j] := i * 3 + j END END;
  Check(16, RowTotal(rows^) = 66);
  Check(17, LEN(rows^, 1) = 3);
  (* characters *)
  NEW(chars, 20);
  COPY("hello", chars^);
  Check(18, chars^ = "hello");
  Check(19, Length(chars^) = 5);
  Check(20, LEN(chars^) = 20);
  local := "abc";
  Check(21, (Length(local) = 3) & (Length("four") = 4));
  Emit("[text]");
  Emit(chars^);
  (* recursion, and an index wider than a word *)
  NEW(cube, 1, 1, 6);
  FOR i := 0 TO 5 DO cube[0, 0, i] := i + 1 END;
  Check(22, Depth(cube[0, 0], 0) = 21);
  wide := 3;
  Check(23, At(cube[0, 0], wide) = 4);
  (* arrays reached through record fields *)
  NEW(holder); NEW(holder.items, 3); NEW(holder.name, 8);
  NEW(holder.items[1]); holder.items[1].value := 9;
  COPY("named", holder.name^);
  Check(24, (LEN(holder.items^) = 3) & (holder.items[1].value = 9));
  Check(25, holder.name^ = "named");
  Check(26, ChainLength(holder.items^, 1) = 1);
  (* records as elements *)
  NEW(points, 3);
  FOR i := 0 TO 2 DO points[i].x := i + 1; points[i].y := i END;
  Check(27, SumPoints(points^) = (10 + 0) + (20 + 1) + (30 + 2));
  (* the collector traces the elements of an array of pointers, though
     they start after its lengths *)
  NEW(nodes, 4);
  FOR i := 0 TO 3 DO NEW(nodes[i]); nodes[i].value := i; nodes[i].next := NIL END;
  Check(28, ChainLength(nodes^, 3) = 1);
  FOR i := 0 TO 49 DO
    NEW(keep[i], 20 + i);
    NEW(keep[i][0]); keep[i][0].value := i;
    NEW(keep[i][19 + i]); keep[i][19 + i].value := i + 1
  END;
  FOR round := 1 TO 400 DO
    NEW(nodes, 300); NEW(chars, 900); NEW(scratch)
  END;
  alive := 0;
  FOR i := 0 TO 49 DO
    IF (LEN(keep[i]^) = 20 + i) & (keep[i][0].value = i) & (keep[i][19 + i].value = i + 1) THEN INC(alive) END
  END;
  Check(29, alive = 50);
  Emit("OK")
END opennew.
