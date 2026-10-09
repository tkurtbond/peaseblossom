MODULE ProcValsOut;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 7): procedure values, printed with Out, so that the program
     built by the LLVM backend and the one built for the VAX can be
     compared: VaxProcVals's checks, and Out's own Ln and String called
     through values. *)
  IMPORT L := VaxProcLib, Out;
  TYPE
    Action = PROCEDURE;
    Writer = PROCEDURE (s: ARRAY OF CHAR);
    Predicate = PROCEDURE (n: INTEGER): BOOLEAN;
    Shape = RECORD sides: INTEGER END;
    Circle = RECORD (Shape) radius: INTEGER END;
    Inspector = PROCEDURE (VAR s: Shape): INTEGER;
    Summer = PROCEDURE (VAR a: ARRAY OF INTEGER): INTEGER;
    Measurer = PROCEDURE (s: ARRAY OF CHAR): INTEGER;
    Wide = PROCEDURE (h: HUGEINT): HUGEINT;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: INTEGER; next: Node END;
    Finder = PROCEDURE (n: INTEGER): Node;
    Chooser = PROCEDURE (i: INTEGER): L.Binary;
    Ops = RECORD add, sub: L.Binary; log: Action END;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: L.Binary; ops: Ops; table: ARRAY 3 OF L.Binary END;
  VAR
    f, g, h: L.Binary; act: Action; even: Predicate; ins: Inspector; summer: Summer;
    measurer: Measurer; wide: Wide; finder: Finder; chooser: Chooser;
    step: PROCEDURE (n: INTEGER): INTEGER;
    ops: Ops; table: ARRAY 4 OF L.Binary; machine: Machine; head: Node;
    circle: Circle; shape: Shape; data: ARRAY 5 OF INTEGER; big: HUGEINT;
    counter, i: INTEGER; write: Writer; line: Action;
    called, statements, tests, compared, passed, held, chosen, installed, tagged, opened,
    found, local, fact, nested, imported: INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b
  END Add;

  PROCEDURE Sub(a, b: INTEGER): INTEGER;
  BEGIN RETURN a - b
  END Sub;

  PROCEDURE Mul(a, b: INTEGER): INTEGER;
  BEGIN RETURN a * b
  END Mul;

  PROCEDURE Bump;
  BEGIN INC(counter)
  END Bump;

  PROCEDURE BumpTwice;
  BEGIN INC(counter, 2)
  END BumpTwice;

  PROCEDURE IsEven(n: INTEGER): BOOLEAN;
  BEGIN RETURN ~ODD(n)
  END IsEven;

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
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k * 10 + SHORT(LEN(s))
  END Measure;

  PROCEDURE Grow(h: HUGEINT): HUGEINT;
  BEGIN RETURN h + h + 1
  END Grow;

  PROCEDURE Find(n: INTEGER): Node;
    VAR p: Node;
  BEGIN
    p := head;
    WHILE (p # NIL) & (p.value # n) DO p := p.next END;
    RETURN p
  END Find;

  PROCEDURE Apply(op: L.Binary; a, b: INTEGER): INTEGER;
  BEGIN RETURN op(a, b)
  END Apply;

  PROCEDURE ApplyVia(op: L.Binary; a, b: INTEGER): INTEGER;
  BEGIN RETURN Apply(op, a, b)
  END ApplyVia;

  PROCEDURE Count(test: Predicate; VAR a: ARRAY OF INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO
      IF test(a[k]) THEN INC(total) END
    END;
    RETURN total
  END Count;

  PROCEDURE Pick(i: INTEGER): L.Binary;
  BEGIN
    IF i = 0 THEN RETURN Add ELSIF i = 1 THEN RETURN Sub ELSIF i = 2 THEN RETURN Mul END;
    RETURN NIL
  END Pick;

  PROCEDURE Install(VAR slot: L.Binary; op: L.Binary);
  BEGIN slot := op
  END Install;

  PROCEDURE Run(act: Action; times: INTEGER);
    VAR k: INTEGER;
  BEGIN
    FOR k := 1 TO times DO act END
  END Run;

  PROCEDURE Fact(n: INTEGER): INTEGER;
  BEGIN
    IF n <= 1 THEN RETURN 1 ELSE RETURN n * step(n - 1) END
  END Fact;

  PROCEDURE Local(): INTEGER;
    VAR op: L.Binary; ops: Ops; locals: ARRAY 2 OF L.Binary;
  BEGIN
    op := Mul; ops.add := op; locals[1] := Sub;
    RETURN 100 * ops.add(3, 4) + locals[1](9, 4)
  END Local;

BEGIN
  f := Add;
  called := f(2, 3) * 100;
  f := Sub; g := f; f := Mul;
  called := called + g(7, 2) * 10 + f(7, 2);

  counter := 0;
  act := Bump; act; act();
  act := BumpTwice; act;
  Run(Bump, 3); Run(act, 2);
  statements := counter;

  FOR i := 0 TO 4 DO data[i] := i + 1 END;
  even := IsEven;
  tests := 0;
  IF even(4) THEN INC(tests, 100) END;
  IF ~even(7) THEN INC(tests, 200) END;
  tests := tests + Count(even, data) * 10 + Count(IsEven, data);

  f := Add; g := Add; h := Sub;
  compared := 0;
  IF f = g THEN INC(compared, 1) END;
  IF (f # h) & (h # f) THEN INC(compared, 2) END;
  g := NIL;
  IF g = NIL THEN INC(compared, 4) END;
  IF (f # NIL) & (f # g) THEN INC(compared, 8) END;
  g := L.Max;
  IF (L.op = g) & (L.op # f) THEN INC(compared, 16) END;

  passed := Apply(Add, 20, 22) * 100 + ApplyVia(Sub, 1, 10);

  ops.add := Add; ops.sub := Sub; ops.log := Bump;
  table[0] := Add; table[1] := Sub; table[2] := Mul;
  i := 2;
  NEW(machine);
  machine.op := Mul; machine.ops.add := Add; machine.table[1] := Sub;
  held := ops.add(1, 2) + ops.sub(5, 3) + table[i](6, 7)
    + machine.op(3, 5) + machine.ops.add(1, 1) + machine.table[1](9, 1);
  counter := 0; ops.log;
  held := held * 10 + counter;
  g := Mul;
  IF (machine.table[0] = NIL) & (machine.ops.log = NIL) & (machine.op = g) THEN INC(held, 10000) END;

  g := Pick(0);
  chosen := g(5, 6) * 100;
  chooser := Pick;
  g := chooser(1);
  chosen := chosen + g(5, 6);
  g := Mul;
  IF (chooser(2) = g) & (chooser(3) = NIL) THEN INC(chosen, 10000) END;

  Install(f, Sub); Install(table[3], Add);
  installed := f(5, 1) * 10 + Apply(table[3], 4, 4);

  ins := Inspect;
  circle.sides := 7; circle.radius := 3; shape.sides := 9;
  tagged := ins(circle) * 100 + ins(shape);

  summer := SumOf; measurer := Measure;
  opened := summer(data) * 100 + measurer("abc");

  wide := Grow;
  big := wide(100000000000);

  NEW(head); head.value := 1;
  NEW(head.next); head.next.value := 2;
  finder := Find;
  found := 0;
  IF finder(2) = head.next THEN INC(found, 1) END;
  IF finder(1) = head THEN INC(found, 2) END;
  IF finder(9) = NIL THEN INC(found, 4) END;

  local := Local();

  step := Fact;
  fact := step(5);

  f := Add; g := Mul;
  nested := f(g(2, 3), table[2](f(1, 1), g(2, 2)));

  imported := L.op(3, 9) * 1000;
  L.op := Mul;
  imported := imported + L.Apply(L.op, 6, 7) * 10 + L.Apply(L.Max, 1, 2);
  h := L.Hidden();
  imported := imported + h(1, 2) * 100;

  write := Out.String; line := Out.Ln;
  write("called "); Out.Int(called, 0); line;
  write("statements "); Out.Int(statements, 0); line;
  write("tests "); Out.Int(tests, 0); line;
  write("compared "); Out.Int(compared, 0); line;
  write("passed "); Out.Int(passed, 0); line;
  write("held "); Out.Int(held, 0); line;
  write("chosen "); Out.Int(chosen, 0); line;
  write("installed "); Out.Int(installed, 0); line;
  write("tagged "); Out.Int(tagged, 0); line;
  write("opened "); Out.Int(opened, 0); line;
  write("big "); Out.Int(big, 0); line;
  write("found "); Out.Int(found, 0); line;
  write("local "); Out.Int(local, 0); line;
  write("fact "); Out.Int(fact, 0); line;
  write("nested "); Out.Int(nested, 0); line;
  write("imported "); Out.Int(imported, 0); write(" calls "); Out.Int(L.calls, 0); line
END ProcValsOut.
