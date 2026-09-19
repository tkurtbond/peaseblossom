MODULE guards;
  (* PLAN.md Phase 9 step 5: type tests (IS), type guards v(T) and WITH on
     an extension hierarchy three levels deep: Shape <- Circle <- Ring,
     and a sibling Square (NIL operands are llvm-pointer-traps'). Each check prints "FAIL nn " on failure; the run
     ends with "OK". *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD
      id: INTEGER
    END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc)
      radius: INTEGER
    END;
    Ring = POINTER TO RingDesc;
    RingDesc = RECORD (CircleDesc)
      inner: INTEGER
    END;
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (ShapeDesc)
      side: INTEGER
    END;
    Holder = POINTER TO HolderDesc;
    HolderDesc = RECORD
      shape: Shape
    END;
  VAR
    s: Shape;
    c: Circle;
    r: Ring;
    q: Square;
    h: Holder;
    result: INTEGER;
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

  (* which branch of a WITH ran: 1 Ring, 2 Circle, 3 Square, 0 the ELSE *)
  PROCEDURE Classify(shape: Shape): INTEGER;
    VAR which: INTEGER;
  BEGIN
    which := 0;
    WITH shape: Ring DO which := 1
    | shape: Circle DO which := 2
    | shape: Square DO which := 3
    ELSE which := 0
    END;
    RETURN which
  END Classify;

  PROCEDURE Area(shape: Shape): INTEGER;
    VAR area: INTEGER;
  BEGIN
    WITH shape: Ring DO area := shape.radius * shape.radius - shape.inner * shape.inner
    | shape: Circle DO area := shape.radius * shape.radius
    | shape: Square DO area := shape.side * shape.side + shape.id * 0
    END;
    RETURN area
  END Area;

  (* string literals inside WITH branches and its ELSE part *)
  PROCEDURE Announce(shape: Shape);
  BEGIN
    WITH shape: Ring DO SysWrite(1, "R", 1)
    | shape: Circle DO SysWrite(1, "C", 1)
    | shape: Square DO SysWrite(1, "S", 1)
    ELSE SysWrite(1, "?", 1)
    END
  END Announce;

BEGIN
  NEW(c); c.id := 1; c.radius := 5;
  NEW(r); r.id := 2; r.radius := 10; r.inner := 6;
  NEW(q); q.id := 3; q.side := 4;
  s := c;
  Check(1, s IS Circle);
  Check(2, ~(s IS Ring));
  Check(3, ~(s IS Square));
  Check(4, s IS Shape);
  s := r;
  Check(5, s IS Ring);
  Check(6, s IS Circle);       (* an extension of the tested type counts *)
  Check(7, ~(s IS Square));
  s := q;
  Check(8, s IS Square);
  Check(9, ~(s IS Circle));

  (* a guard as an expression and inside a designator *)
  s := r;
  c := s(Circle);
  Check(10, c.radius = 10);
  Check(11, s(Ring).inner = 6);
  Check(12, s(Circle).radius = 10);
  r := s(Ring);
  Check(13, r.id = 2);
  s(Ring).inner := 8;
  Check(14, r.inner = 8);

  (* WITH picks the first branch whose test holds, and narrows the variable *)
  Check(15, Classify(r) = 1);
  NEW(c); c.radius := 3; s := c;
  Check(16, Classify(s) = 2);
  Check(17, Classify(q) = 3);
  NEW(s);
  Check(18, Classify(s) = 0);
  s := r;
  Check(19, Area(s) = 100 - 64);
  s := c;
  Check(20, Area(s) = 9);
  s := q;
  Check(21, Area(s) = 16);

  (* a guard reaching through a pointer field *)
  NEW(h);
  h.shape := r;
  Check(22, h.shape IS Ring);
  Check(23, h.shape(Ring).radius = 10);
  h.shape := q;
  Check(24, h.shape(Square).side = 4);
  Check(25, ~(h.shape IS Circle));

  (* WITH on a global variable, assignment to a field through the narrowed type *)
  s := r;
  WITH s: Ring DO s.inner := 1; s.radius := 2 END;
  Check(26, (r.inner = 1) & (r.radius = 2));
  result := 0;
  WITH s: Circle DO result := 1 | s: Ring DO result := 2 END;   (* Circle is tried first *)
  Check(27, result = 1);
  Announce(r); Announce(c); Announce(q);
  SysWrite(1, "OK", 2)
END guards.
