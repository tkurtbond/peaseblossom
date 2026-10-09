MODULE VaxMethLib;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 6): VaxMethods's import, whose type-bound procedures its
     extensions inherit and override: Shape's with pointer receivers, one
     hidden, Code calling two through its receiver's ProcTab; Counter's
     with VAR receivers, AddAll's an open-array parameter after the
     receiver and its tag; and variables whose procedures an importer
     calls. *)
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD x*: INTEGER END;
    Circle* = POINTER TO CircleDesc;
    CircleDesc* = RECORD (ShapeDesc) r*: INTEGER END;
    Counter* = RECORD n*: INTEGER END;
  VAR
    shared*: Shape; total*: Counter;

  PROCEDURE (s: Shape) Area*(): INTEGER;
  BEGIN RETURN 0
  END Area;

  PROCEDURE (s: Shape) Hidden(): INTEGER;
  BEGIN RETURN 10 + s.x
  END Hidden;

  PROCEDURE (s: Shape) Code*(): INTEGER;
  BEGIN RETURN s.Hidden() * 100 + s.Area()
  END Code;

  PROCEDURE (c: Circle) Area*(): INTEGER;
  BEGIN RETURN 3 * c.r * c.r
  END Area;

  PROCEDURE (c: Circle) Hidden(): INTEGER;
  BEGIN RETURN 20 + c.r
  END Hidden;

  PROCEDURE (VAR c: Counter) Add*(k: INTEGER);
  BEGIN c.n := c.n + k
  END Add;

  PROCEDURE (VAR c: Counter) Get*(): INTEGER;
  BEGIN RETURN c.n
  END Get;

  PROCEDURE (VAR c: Counter) AddAll*(a: ARRAY OF INTEGER; VAR last: INTEGER);
    VAR i: LONGINT;
  BEGIN
    FOR i := 0 TO LEN(a) - 1 DO c.Add(a[i]) END;
    last := a[LEN(a) - 1]
  END AddAll;

BEGIN
  NEW(shared); shared.x := 9; total.n := 1000
END VaxMethLib.
