MODULE client;
  (* PLAN.md Phase 9 step 5 across a module boundary: a pointer type,
     constructor and hidden field from shapelib; NEW of an imported record
     from here and of a local extension of it (its layout is the importer's
     own computation from the .sym, hidden field included); IS and guards
     against imported and local types; a WITH over both; and a chain that
     mixes objects allocated in either module, walked while the collector
     runs under a small heap cap. Each check prints "FAIL nn " on
     failure; the run ends with "OK". *)
  IMPORT Lib := shapelib, GarbageCollectedHeap;
  TYPE
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (Lib.ShapeDesc)
      side: INTEGER
    END;
  VAR
    a, b: Lib.Shape;
    c: Lib.Circle;
    q: Square;
    p: Lib.Shape;
    kept, count, total: LONGINT;
    i: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR text: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      text[0] := "F"; text[1] := "A"; text[2] := "I"; text[3] := "L"; text[4] := " ";
      text[5] := CHR(ORD("0") + number DIV 10); text[6] := CHR(ORD("0") + number MOD 10);
      text[7] := " "; text[8] := 0X;
      SysWrite(1, text, 8)
    END
  END Check;

  PROCEDURE Describe(s: Lib.Shape): INTEGER;
    VAR which: INTEGER;
  BEGIN
    WITH s: Square DO which := 3
    | s: Lib.Circle DO which := 2
    | s: Lib.Shape DO which := 1
    END;
    RETURN which
  END Describe;

BEGIN
  GarbageCollectedHeap.SetHeapLimit(600000);
  a := Lib.NewShape(1);
  c := Lib.NewCircle(2, 9);
  Check(1, (a.id = 1) & (c.id = 2) & (c.radius = 9));
  Check(2, (Lib.Hidden(a) = 1001) & (Lib.Hidden(c) = 2002));
  Check(3, (Lib.created = 2) & (Lib.registry = c) & (c.next = a) & (a.next = NIL));

  (* an extension declared here, allocated here, linked into lib's registry *)
  NEW(q); q.id := 3; q.side := 4; q.next := Lib.registry; Lib.registry := q;
  Check(4, (q.side = 4) & (q.id = 3) & (Lib.registry.next = c));
  Check(5, Lib.Hidden(q) = 0);      (* the hidden field is there, and zero *)

  (* type tests across the boundary *)
  p := q;
  Check(6, (p IS Square) & (p IS Lib.Shape) & ~(p IS Lib.Circle));
  p := c;
  Check(7, (p IS Lib.Circle) & ~(p IS Square));
  Check(8, (p(Lib.Circle).radius = 9));
  p := a;
  Check(9, ~(p IS Lib.Circle) & ~(p IS Square));
  Check(10, (Describe(a) = 1) & (Describe(c) = 2) & (Describe(q) = 3));

  (* NEW in both modules while the collector runs; everything stays linked *)
  FOR i := 1 TO 20000 DO
    b := Lib.NewShape(i + 10);
    IF i MOD 100 = 0 THEN Lib.registry := b; Lib.registry.next := c END
  END;
  Check(11, GarbageCollectedHeap.CollectionCount() > 0);
  Check(12, (Lib.registry.next = c) & (c.next = a) & (a.next = NIL) & (c.radius = 9));
  count := 0; total := 0; p := Lib.registry;
  WHILE p # NIL DO INC(count); total := total + Lib.Hidden(p); p := p.next END;
  Check(13, count = 3);
  Check(14, total = (1000 + 20000 + 10) + 2002 + 1001);
  SysWrite(1, "OK", 2)
END client.
