MODULE procvals;
  (* PLAN.md Phase 9 step 8: procedure values (Oberon2.pdf 6.5) - a
     procedure assigned to a variable, a record field or an array element,
     passed as an argument, returned from a function, compared with another
     or with NIL, and called through any of those. A procedure type's
     parameters travel exactly as an ordinary call's: a VAR record parameter
     brings its type tag (so WITH and IS work in the callee) and an open
     array its lengths. Each check prints "FAIL nn " on failure; the run
     ends with "OK". *)
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Predicate = PROCEDURE (n: INTEGER): BOOLEAN;
    Scale = PROCEDURE (x: REAL): REAL;
    Shape = RECORD sides: INTEGER END;
    Circle = RECORD (Shape) radius: INTEGER END;
    Inspector = PROCEDURE (VAR s: Shape): INTEGER;
    Summer = PROCEDURE (VAR a: ARRAY OF INTEGER): INTEGER;
    Measurer = PROCEDURE (s: ARRAY OF CHAR): INTEGER;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: INTEGER; next: Node END;
    Finder = PROCEDURE (n: INTEGER): Node;
    Ops = RECORD add, sub: Binary; log: Action END;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary; ops: Ops; table: ARRAY 3 OF Binary END;
    Chooser = PROCEDURE (i: INTEGER): Binary;
    Unary = PROCEDURE (n: INTEGER): INTEGER;
    Item = POINTER TO ItemDesc;
    ItemDesc = RECORD op: Binary; next: Item; k: INTEGER END;
  VAR
    f, g, h: Binary; step: Unary;
    act: Action;
    even: Predicate;
    twice: Scale;
    ins: Inspector;
    summer: Summer;
    measurer: Measurer;
    finder: Finder;
    ops: Ops;
    table: ARRAY 4 OF Binary;
    machine: Machine;
    chooser: Chooser;
    counter, i, n: INTEGER;
    x: REAL;
    circle: Circle; shape: Shape;
    data: ARRAY 5 OF INTEGER;
    head: Node;
    junk: Node;
    items, item: Item; total: INTEGER;
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

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

  PROCEDURE Sub(a, b: INTEGER): INTEGER;
  BEGIN RETURN a - b END Sub;

  PROCEDURE Mul(a, b: INTEGER): INTEGER;
  BEGIN RETURN a * b END Mul;

  PROCEDURE Bump;
  BEGIN INC(counter) END Bump;

  PROCEDURE BumpTwice;
  BEGIN INC(counter, 2) END BumpTwice;

  PROCEDURE IsEven(n: INTEGER): BOOLEAN;
  BEGIN RETURN ~ODD(n) END IsEven;

  PROCEDURE Double(x: REAL): REAL;
  BEGIN RETURN x * 2.0 END Double;

  (* the tag a VAR record parameter carries reaches the callee even when
     the call goes through a procedure value *)
  PROCEDURE Inspect(VAR s: Shape): INTEGER;
  BEGIN
    IF s IS Circle THEN
      WITH s: Circle DO RETURN s.radius * 100 + s.sides END
    END;
    RETURN s.sides
  END Inspect;

  PROCEDURE SumOf(VAR a: ARRAY OF INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO total := total + a[k] END;
    RETURN total
  END SumOf;

  PROCEDURE Measure(s: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN Length(s) * 10 + SHORT(LEN(s)) END Measure;

  PROCEDURE Find(n: INTEGER): Node;
    VAR p: Node;
  BEGIN
    p := head;
    WHILE (p # NIL) & (p.value # n) DO p := p.next END;
    RETURN p
  END Find;

  PROCEDURE Apply(op: Binary; a, b: INTEGER): INTEGER;
  BEGIN RETURN op(a, b) END Apply;

  (* a procedure value handed on unchanged, two levels down *)
  PROCEDURE ApplyVia(op: Binary; a, b: INTEGER): INTEGER;
  BEGIN RETURN Apply(op, a, b) END ApplyVia;

  PROCEDURE Fold(op: Binary; VAR a: ARRAY OF INTEGER; start: INTEGER): INTEGER;
    VAR k, acc: INTEGER;
  BEGIN
    acc := start;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO acc := op(acc, a[k]) END;
    RETURN acc
  END Fold;

  PROCEDURE Count(test: Predicate; VAR a: ARRAY OF INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO
      IF test(a[k]) THEN INC(total) END
    END;
    RETURN total
  END Count;

  PROCEDURE Pick(i: INTEGER): Binary;
  BEGIN
    IF i = 0 THEN RETURN Add ELSIF i = 1 THEN RETURN Sub ELSIF i = 2 THEN RETURN Mul END;
    RETURN NIL
  END Pick;

  PROCEDURE Install(VAR slot: Binary; op: Binary);
  BEGIN slot := op END Install;

  PROCEDURE Run(act: Action; times: INTEGER);
    VAR k: INTEGER;
  BEGIN
    FOR k := 1 TO times DO act END
  END Run;

  (* recursion through a procedure variable *)
  PROCEDURE Fact(n: INTEGER): INTEGER;
  BEGIN
    IF n <= 1 THEN RETURN 1 ELSE RETURN n * step(n - 1) END
  END Fact;

  PROCEDURE Local(): LONGINT;
    VAR op: Binary; ops: Ops; locals: ARRAY 2 OF Binary;
  BEGIN
    op := Mul; ops.add := op; locals[1] := Sub;
    RETURN 1000 * ops.add(3, 4) + 100000 * locals[1](9, 4)
  END Local;

BEGIN
  (* 1-4: assign, call in an expression, reassign *)
  f := Add;
  Check(1, f(2, 3) = 5);
  f := Sub;
  Check(2, f(2, 3) = -1);
  n := f(10, 4) + Add(1, 1);
  Check(3, n = 8);
  g := f;
  f := Mul;
  Check(4, (g(7, 2) = 5) & (f(7, 2) = 14));

  (* 5-7: a proper procedure with no parameters, as a statement *)
  counter := 0;
  act := Bump;
  act; act;
  Check(5, counter = 2);
  act := BumpTwice;
  act();
  Check(6, counter = 4);
  Run(Bump, 3); Run(act, 2);
  Check(7, counter = 3 + 4 + 4);

  (* 8-9: BOOLEAN and REAL results *)
  even := IsEven;
  Check(8, even(4) & ~even(7));
  twice := Double;
  x := twice(1.25);
  Check(9, x = 2.5);

  (* 10-11: comparison *)
  f := Add; g := Add; h := Sub;
  Check(10, (f = g) & (f # h) & (h # f));
  g := NIL;
  Check(11, (g = NIL) & (f # NIL) & (f # g));

  (* 12-15: passed as an argument, and on again *)
  Check(12, Apply(Add, 20, 22) = 42);
  Check(13, Apply(f, 1, 2) = 3);
  Check(14, ApplyVia(Mul, 6, 7) = 42);
  Check(15, ApplyVia(Sub, 1, 10) = -9);

  (* 16-18: through record fields, a pointer's fields and array elements *)
  ops.add := Add; ops.sub := Sub; ops.log := Bump;
  Check(17, ops.add(1, 2) + ops.sub(5, 3) = 5);
  counter := 0; ops.log; Check(16, counter = 1);
  table[0] := Add; table[1] := Sub; table[2] := Mul;
  i := 2;
  Check(18, table[i](6, 7) = 42);
  NEW(machine);
  machine.op := Mul;
  machine.ops.add := Add;
  machine.table[1] := Sub;
  g := Mul;
  Check(19, machine.op = g);
  Check(20, machine.op(3, 5) + machine.ops.add(1, 1) + machine.table[1](9, 1) = 25);
  Check(21, (machine.table[0] = NIL) & (machine.ops.log = NIL));

  (* 22-23: a function that returns one *)
  g := Pick(0);
  Check(22, g(5, 6) = 11);
  chooser := Pick; g := Mul;
  Check(23, (chooser(2) = g) & (chooser(3) = NIL));
  g := chooser(1);
  Check(38, g(5, 6) = -1);

  (* 24-25: a VAR parameter of procedure type, and passing an element *)
  Install(f, Sub);
  Check(24, f(5, 1) = 4);
  Install(table[3], Add);
  Check(25, Apply(table[3], 4, 4) = 8);

  (* 26-27: a VAR record parameter's tag survives the call *)
  ins := Inspect;
  circle.sides := 7; circle.radius := 3;
  Check(26, ins(circle) = 307);
  shape.sides := 9;
  Check(27, ins(shape) = 9);

  (* 28-31: open arrays, VAR and value *)
  FOR i := 0 TO 4 DO data[i] := i + 1 END;
  summer := SumOf;
  Check(28, summer(data) = 15);
  measurer := Measure;
  Check(29, measurer("abc") = 34);
  Check(30, Fold(Add, data, 0) = 15);
  Check(31, Fold(Mul, data, 1) = 120);
  Check(32, Count(IsEven, data) = 2);
  Check(33, Count(even, data) = 2);

  (* 34-36: a function returning a pointer, through a value *)
  NEW(head); head.value := 1;
  NEW(head.next); head.next.value := 2;
  finder := Find;
  Check(34, (finder(2) = head.next) & (finder(1) = head) & (finder(9) = NIL));
  junk := finder(2);
  Check(35, junk.value = 2);

  (* 36: locals holding procedures *)
  Check(36, Local() = 512000);

  (* 37: still callable after the collector has run over a lot of garbage *)
  machine.op := Add;
  FOR i := 1 TO 3000 DO NEW(junk); NEW(junk.next) END;
  Check(37, machine.op(2, 2) = 4);

  (* 39-40: a record mixing procedure and pointer fields is traced whole by
     the collector - the list survives a lot of churn, procedures intact *)
  items := NIL;
  FOR i := 1 TO 200 DO
    NEW(item); item.op := Add; item.k := i; item.next := items; items := item
  END;
  FOR i := 1 TO 3000 DO NEW(junk); NEW(junk.next) END;
  total := 0; item := items;
  WHILE item # NIL DO total := item.op(total, item.k); item := item.next END;
  Check(39, total = 20100);
  Check(40, items.op = machine.op);

  (* 41: recursion through a procedure variable *)
  step := Fact;
  Check(41, step(5) = 120);

  SysWrite(1, "OK", 2)
END procvals.
