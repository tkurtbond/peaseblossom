MODULE NestedOut;
  IMPORT Out;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 8): nested procedures, printed with Out, so that the program
     built by the LLVM backend and the one built for the VAX can be
     compared: VaxNested's checks. *)
  TYPE
    Shape = RECORD sides: INTEGER END;
    Circle = RECORD (Shape) r: INTEGER END;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD val: INTEGER; next: Node END;
    Counter = POINTER TO CounterDesc;
    CounterDesc = RECORD n: INTEGER END;
  VAR
    basic, deep, parity, params, record, opened, method, recursive, built, cousins, mode, v: INTEGER;
    huge: HUGEINT; c: Circle; sh: Shape; arr: ARRAY 4 OF INTEGER; cnt: Counter;

  PROCEDURE Basic(): INTEGER;
    VAR n: INTEGER;
    PROCEDURE Add(k: INTEGER);
    BEGIN n := n + k
    END Add;
  BEGIN
    n := 1; Add(2); Add(3); RETURN n
  END Basic;

  PROCEDURE Deep(a: INTEGER): INTEGER;
    VAR b: INTEGER;
    PROCEDURE Middle(): INTEGER;
      VAR m: INTEGER;
      PROCEDURE Inner(): INTEGER;
      BEGIN b := b + 1; RETURN a * 100 + m * 10 + b
      END Inner;
    BEGIN m := 7; RETURN Inner()
    END Middle;
  BEGIN
    b := 2; a := a + 1; RETURN Middle()
  END Deep;

  PROCEDURE Parity(n: INTEGER): INTEGER;
    VAR calls: INTEGER;
    PROCEDURE ^ Odd(k: INTEGER): BOOLEAN;
    PROCEDURE Even(k: INTEGER): BOOLEAN;
    BEGIN
      INC(calls); IF k = 0 THEN RETURN TRUE ELSE RETURN Odd(k - 1) END
    END Even;
    PROCEDURE Odd(k: INTEGER): BOOLEAN;
    BEGIN
      INC(calls); IF k = 0 THEN RETURN FALSE ELSE RETURN Even(k - 1) END
    END Odd;
  BEGIN
    calls := 0;
    IF Even(n) THEN RETURN calls * 10 + 1 ELSE RETURN calls * 10 END
  END Parity;

  PROCEDURE Params(VAR v: INTEGER; w: INTEGER);
    PROCEDURE Set;
    BEGIN v := v * 10 + w
    END Set;
  BEGIN
    Set; Set
  END Params;

  PROCEDURE Kind(VAR s: Shape): INTEGER;
    PROCEDURE Test(): INTEGER;
    BEGIN
      IF s IS Circle THEN RETURN s(Circle).r * 10 + s.sides ELSE RETURN s.sides END
    END Test;
  BEGIN
    RETURN Test()
  END Kind;

  PROCEDURE Sum(a: ARRAY OF INTEGER; VAR b: ARRAY OF INTEGER): INTEGER;
    PROCEDURE Add(): INTEGER;
      VAR k, t: INTEGER;
    BEGIN
      t := 0;
      FOR k := 0 TO SHORT(LEN(a)) - 1 DO t := t + a[k] * b[k]; b[k] := 0 END;
      a[0] := 99;
      IF mode = 2 THEN k := SHORT(LEN(a)); t := a[k] END;
      RETURN t
    END Add;
  BEGIN
    RETURN Add() + a[0] + b[1]
  END Sum;

  PROCEDURE Wide(h: HUGEINT): HUGEINT;
    VAR q: HUGEINT;
    PROCEDURE Grow;
    BEGIN q := q + h; h := h + h
    END Grow;
  BEGIN
    q := 1; Grow; Grow; RETURN q + h
  END Wide;

  PROCEDURE (c: Counter) Bump(k: INTEGER): INTEGER;
    PROCEDURE Once;
    BEGIN
      IF mode = 1 THEN c := NIL END;
      INC(c.n, k)
    END Once;
  BEGIN
    Once; Once; RETURN c.n
  END Bump;

  PROCEDURE Tree(depth: INTEGER): INTEGER;
    VAR here: INTEGER;
    PROCEDURE Visit(): INTEGER;
    BEGIN
      IF depth > 0 THEN here := Tree(depth - 1) + depth ELSE here := 0 END;
      RETURN here
    END Visit;
  BEGIN
    here := -1; RETURN Visit() * 10 + depth
  END Tree;

  PROCEDURE Build(n: INTEGER): INTEGER;
    VAR head: Node; k, t: INTEGER;
    PROCEDURE Push(v: INTEGER);
      VAR p: Node;
    BEGIN
      NEW(p); p.val := v; p.next := head; head := p
    END Push;
  BEGIN
    head := NIL;
    FOR k := 1 TO n DO Push(k) END;
    t := 0;
    WHILE head # NIL DO t := t * 10 + head.val; head := head.next END;
    RETURN t
  END Build;

  PROCEDURE Cousins(): INTEGER;
    VAR x: INTEGER;
    PROCEDURE A(k: INTEGER);
    BEGIN x := x * 10 + k
    END A;
    PROCEDURE B(): INTEGER;
      PROCEDURE C;
      BEGIN A(3)
      END C;
    BEGIN
      A(2); C; RETURN x
    END B;
  BEGIN
    x := 1; RETURN B()
  END Cousins;

BEGIN
  basic := Basic();
  deep := Deep(4);
  parity := Parity(7) * 100 + Parity(4);
  v := 1; Params(v, 3); params := v;
  c.sides := 3; c.r := 5; sh.sides := 4;
  record := Kind(c) * 100 + Kind(sh);
  arr[0] := 1; arr[1] := 2; arr[2] := 3; arr[3] := 4;
  opened := Sum(arr, arr) * 10 + arr[3];
  huge := Wide(10000000000);
  NEW(cnt); cnt.n := 1;
  method := cnt.Bump(4);
  recursive := Tree(3);
  built := Build(4);
  cousins := Cousins();
  Out.String("basic "); Out.Int(basic, 0); Out.Ln;
  Out.String("deep "); Out.Int(deep, 0); Out.Ln;
  Out.String("parity "); Out.Int(parity, 0); Out.Ln;
  Out.String("params "); Out.Int(params, 0); Out.Ln;
  Out.String("record "); Out.Int(record, 0); Out.Ln;
  Out.String("opened "); Out.Int(opened, 0); Out.Ln;
  Out.String("huge "); Out.Int(huge, 0); Out.Ln;
  Out.String("method "); Out.Int(method, 0); Out.Ln;
  Out.String("recursive "); Out.Int(recursive, 0); Out.Ln;
  Out.String("built "); Out.Int(built, 0); Out.Ln;
  Out.String("cousins "); Out.Int(cousins, 0); Out.Ln
END NestedOut.
