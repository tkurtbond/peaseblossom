MODULE bound;
  (* PLAN.md Phase 9 step 6: type-bound procedures and dispatch.
     Shape <- Circle <- Ring, and a sibling Square, bound to pointer
     receivers; Point <- Point3 bound to VAR (record) receivers. Each check
     prints "FAIL nn " on failure; the run ends with "OK". *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD id: INTEGER END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc) radius: INTEGER END;
    Ring = POINTER TO RingDesc;
    RingDesc = RECORD (CircleDesc) inner: INTEGER END;
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (ShapeDesc) side: INTEGER END;
    Holder = POINTER TO HolderDesc;
    HolderDesc = RECORD shape: Shape END;

    Point = RECORD x, y: INTEGER END;
    Point3 = RECORD (Point) z: INTEGER END;
    PointPtr = POINTER TO Point;
    Point3Ptr = POINTER TO Point3;
    Cell = POINTER TO CellDesc;
    CellDesc = RECORD p: Point3; q: Point END;
    (* a record written inline under its pointer type has bound procedures too *)
    Counter = POINTER TO RECORD count: INTEGER END;
  VAR
    s: Shape; c: Circle; r: Ring; q: Square; h: Holder;
    shapes: ARRAY 3 OF Shape;
    pt: Point; p3: Point3; row: ARRAY 3 OF Point3;
    pp: PointPtr; p3p: Point3Ptr; cell: Cell; counter: Counter;
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

  (* ---- pointer receivers ---- *)

  PROCEDURE (s: Shape) Area(): INTEGER;
  BEGIN RETURN 0 END Area;

  PROCEDURE (s: Shape) Name(): INTEGER;
  BEGIN RETURN 1 END Name;

  (* dispatches on its own receiver: Name and Area are the dynamic type's *)
  PROCEDURE (s: Shape) Describe(): INTEGER;
  BEGIN RETURN s.Name() * 1000 + s.Area() END Describe;

  PROCEDURE (s: Circle) Area(): INTEGER;
  BEGIN RETURN s.radius * s.radius END Area;

  PROCEDURE (s: Circle) Name(): INTEGER;
  BEGIN RETURN 2 END Name;

  (* Name is inherited from Circle; Area extends Circle's through "^";
     Hole is new, so it gets a slot of its own *)
  PROCEDURE (s: Ring) Area(): INTEGER;
  BEGIN RETURN s.Area^() - s.inner * s.inner END Area;

  PROCEDURE (s: Ring) Hole(): INTEGER;
  BEGIN RETURN s.inner END Hole;

  PROCEDURE (s: Square) Area(): INTEGER;
  BEGIN RETURN s.side * s.side END Area;

  PROCEDURE (s: Square) Name(): INTEGER;
  BEGIN RETURN 3 END Name;

  (* a proper procedure with a parameter, changing the object *)
  PROCEDURE (s: Square) Scale(k: INTEGER);
  BEGIN s.side := s.side * k END Scale;

  (* the receiver is an ordinary value parameter: assignable *)
  PROCEDURE (me: Circle) Twice(): INTEGER;
    VAR total: INTEGER;
  BEGIN
    total := me.Area();
    me := NIL;
    RETURN total + total
  END Twice;

  (* ---- VAR receivers ---- *)

  PROCEDURE (VAR p: Point) Sum(): INTEGER;
  BEGIN RETURN p.x + p.y END Sum;

  PROCEDURE (VAR p: Point3) Sum(): INTEGER;
  BEGIN RETURN p.Sum^() + p.z END Sum;

  (* inherited by Point3, and dispatching on its VAR receiver's real type *)
  PROCEDURE (VAR p: Point) Twice(): INTEGER;
  BEGIN RETURN 2 * p.Sum() END Twice;

  PROCEDURE (VAR p: Point) Move(dx: INTEGER);
  BEGIN p.x := p.x + dx END Move;

  (* a VAR record parameter of a type-bound procedure, passed on *)
  PROCEDURE (s: Shape) Total(VAR p: Point): INTEGER;
  BEGIN RETURN s.id + p.Sum() END Total;

  PROCEDURE (k: Counter) Bump(by: INTEGER): INTEGER;
  BEGIN k.count := k.count + by; RETURN k.count END Bump;

  (* receivers that are locals: a pointer, a record, an array of records *)
  PROCEDURE Locals(): INTEGER;
    VAR shape: Shape; ring: Ring; point: Point3; points: ARRAY 2 OF Point3;
  BEGIN
    NEW(ring); ring.id := 1; ring.radius := 4; ring.inner := 2;
    shape := ring;
    point.x := 1; point.y := 2; point.z := 3;
    points[1].x := 10; points[1].y := 20; points[1].z := 30;
    RETURN shape.Area() + shape.Name() * 100 + point.Sum() * 1000 + points[1].Sum() DIV 10
  END Locals;

BEGIN
  NEW(c); c.id := 1; c.radius := 5;
  NEW(r); r.id := 2; r.radius := 10; r.inner := 6;
  NEW(q); q.id := 3; q.side := 4;

  (* the call goes to the dynamic type's procedure, not the declared one's *)
  s := c;
  Check(1, s.Area() = 25);
  Check(2, s.Name() = 2);
  s := r;
  Check(3, s.Area() = 100 - 36);
  Check(4, s.Name() = 2);       (* Ring inherits Circle's *)
  s := q;
  Check(5, s.Area() = 16);
  Check(6, s.Name() = 3);
  NEW(s);
  Check(7, s.Area() = 0);
  Check(8, s.Name() = 1);

  (* through the more specific static types *)
  Check(9, c.Area() = 25);
  Check(10, r.Area() = 64);
  Check(11, q.Area() = 16);
  Check(12, r.Hole() = 6);

  (* a procedure calling its receiver's other procedures *)
  s := c; Check(13, s.Describe() = 2025);
  s := r; Check(14, s.Describe() = 2064);
  s := q; Check(15, s.Describe() = 3016);
  NEW(s); s.id := 9; Check(16, s.Describe() = 1000);
  Check(17, r.Describe() = 2064);

  (* receivers that are fields, array elements, guards and WITH variables *)
  NEW(h);
  h.shape := r; Check(18, h.shape.Area() = 64);
  h.shape := q; Check(19, h.shape.Area() = 16);
  shapes[0] := c; shapes[1] := r; shapes[2] := q;
  Check(20, shapes[0].Name() = 2);
  Check(21, shapes[1].Name() = 2);
  Check(22, shapes[2].Name() = 3);
  s := r;
  Check(23, s(Ring).Hole() = 6);
  Check(24, s(Circle).Area() = 64);   (* a guard does not change the dynamic type *)
  WITH s: Ring DO Check(25, s.Hole() = 6); Check(26, s.Area() = 64) END;

  (* a proper procedure with a parameter *)
  q.side := 5; q.Scale(3);
  Check(27, q.side = 15);
  s := q; Check(28, s.Area() = 225);

  (* the receiver parameter is a private copy *)
  Check(29, c.Twice() = 50);
  Check(30, c # NIL);

  (* ---- VAR receivers ---- *)
  pt.x := 1; pt.y := 2;
  p3.x := 10; p3.y := 20; p3.z := 30;
  Check(31, pt.Sum() = 3);
  Check(32, p3.Sum() = 60);                    (* Point3's, calling Point's through "^" *)
  Check(33, pt.Twice() = 6);
  Check(34, p3.Twice() = 120);                 (* the inherited Twice sees a Point3 *)
  pt.Move(4); Check(35, pt.x = 5);
  p3.Move(1); Check(36, p3.Sum() = 61);

  (* elements and fields of records *)
  row[0].x := 1; row[0].y := 1; row[0].z := 1;
  row[2].x := 5; row[2].y := 5; row[2].z := 5;
  Check(37, row[0].Sum() = 3);
  Check(38, row[2].Twice() = 30);
  NEW(cell);
  cell.p.x := 2; cell.p.y := 3; cell.p.z := 4;
  cell.q.x := 7; cell.q.y := 8;
  Check(39, cell.p.Sum() = 9);
  Check(40, cell.q.Sum() = 15);
  Check(41, cell.p.Twice() = 18);

  (* a pointer to a record is a receiver too, and a pointer to the base
     type holding an extension dispatches on what is in the heap block *)
  NEW(p3p); p3p.x := 1; p3p.y := 2; p3p.z := 3;
  Check(42, p3p.Sum() = 6);
  Check(43, p3p^.Sum() = 6);
  pp := p3p;
  Check(44, pp.Sum() = 6);
  Check(45, pp.Twice() = 12);
  NEW(pp); pp.x := 1; pp.y := 2;
  Check(46, pp.Sum() = 3);
  Check(47, pp.Twice() = 6);

  (* the VAR parameter of a bound procedure keeps its actual's type *)
  s := q; q.id := 10;
  Check(48, s.Total(pt) = 10 + 7);
  Check(49, s.Total(p3) = 10 + 61);
  pp := p3p;
  Check(50, s.Total(pp^) = 10 + 6);
  Check(51, s.Total(cell.p) = 10 + 9);
  Check(52, s.Total(row[2]) = 10 + 15);
  Check(53, Locals() = 12 + 200 + 6000 + 6);

  (* a short-circuited operand that itself dispatches *)
  NEW(s); s := NIL;
  Check(56, ~((s # NIL) & (s.Area() = 0)));
  s := c;
  Check(57, (s # NIL) & (s.Area() = 25));
  Check(58, (s = NIL) OR (s.Area() = 25));

  (* last, because real voc gives the anonymous record no usable type
     descriptor and traps "NIL access" on a bound call through it *)
  NEW(counter);
  Check(54, counter.Bump(2) = 2);
  Check(55, counter.Bump(3) = 5);
  SysWrite(1, "OK", 2)
END bound.
