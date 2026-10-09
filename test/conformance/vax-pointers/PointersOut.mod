MODULE PointersOut;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, items 3 and 4): pointers, printed with Out, so that the program
     built by the LLVM backend and the one built for the VAX can be
     compared: lists, NIL, pointers to records, to fixed arrays and to open
     arrays of one and two dimensions, LEN, COPY and comparisons through
     them, a pointer type local to a procedure. *)
  IMPORT Out;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: INTEGER; next: Node END;
    Pair* = POINTER TO RECORD left*, right*: Node; name: ARRAY 8 OF CHAR END;
    Text = POINTER TO ARRAY OF CHAR;
    Grid = POINTER TO ARRAY OF ARRAY OF INTEGER;
    Row = POINTER TO ARRAY 4 OF INTEGER;
    Nodes = POINTER TO ARRAY 3 OF Node;
  VAR
    list, n: Node; pair: Pair; t, u: Text; g: Grid; r: Row; ns: Nodes;
    i, j, sum: INTEGER;

  PROCEDURE Push(VAR head: Node; v: INTEGER);
    VAR p: Node;
  BEGIN
    NEW(p); p.value := v; p.next := head; head := p
  END Push;

  PROCEDURE Last(p: Node): Node;
  BEGIN
    IF p # NIL THEN WHILE p.next # NIL DO p := p.next END END;
    RETURN p
  END Last;

  PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN
    k := 0; WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k
  END Length;

  PROCEDURE Local(): INTEGER;
    TYPE Cell = POINTER TO RECORD a, b: INTEGER END;
    VAR c: Cell;
  BEGIN
    NEW(c); c.a := 20; c.b := 22; RETURN c.a + c.b
  END Local;

BEGIN
  list := NIL;
  IF list = NIL THEN Out.String("empty") END; Out.Ln;
  FOR i := 1 TO 5 DO Push(list, i * 10) END;
  n := list; sum := 0;
  WHILE n # NIL DO Out.Int(n.value, 4); sum := sum + n^.value; n := n.next END;
  Out.Int(sum, 6); Out.Ln;
  n := Last(list); Out.Int(n.value, 0); Out.Char(" "); Out.Int(list.next.next.value, 0); Out.Ln;
  NEW(pair); pair.left := list; pair.right := Last(list); pair.name := "pair";
  Out.String(pair.name); Out.Int(pair.left.value + pair.right.value, 4);
  IF pair.left # pair.right THEN Out.String(" differ") END; Out.Ln;
  NEW(t, 12); COPY("hello", t^); Out.String(t^); Out.Int(LEN(t^), 4); Out.Int(Length(t^), 4); Out.Ln;
  NEW(u, 6); COPY("hello", u^);
  IF t^ = u^ THEN Out.String("same") END; IF u^ < "help" THEN Out.String(" less") END; Out.Ln;
  t[0] := "j"; Out.String(t^); Out.Char(" "); Out.Char(u[4]); Out.Ln;
  NEW(g, 3, 4);
  FOR i := 0 TO 2 DO FOR j := 0 TO 3 DO g[i, j] := i * 10 + j END END;
  Out.Int(LEN(g^), 3); Out.Int(LEN(g^, 1), 3); Out.Int(g[2, 3], 4); Out.Int(g^[1][2], 4); Out.Ln;
  NEW(r); r[3] := 7; r^[0] := r[3] * 2; Out.Int(r[0] + r[3], 0); Out.Ln;
  NEW(ns); ns[0] := list; ns[2] := Last(list);
  IF ns[1] = NIL THEN Out.Int(ns[0].value + ns[2]^.value, 0) END; Out.Ln;
  Out.Int(Local(), 0); Out.Ln;
  Out.String("done"); Out.Ln
END PointersOut.
