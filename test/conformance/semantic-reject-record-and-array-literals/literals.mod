MODULE Bad;
  IMPORT lib;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Vector = ARRAY 3 OF REAL;
    P = POINTER TO Point;
    Ints = POINTER TO ARRAY OF INTEGER;
  VAR p: Point; v: Vector; o: lib.Open; h: lib.Hidden; r: lib.ReadOnly; s: lib.Sub; w: lib.Wrap;
    ptr: P; i: INTEGER;
  PROCEDURE Change(VAR pt: Point);
  END Change;
BEGIN
  p := Point{x := 1, z := 2};
  p := Point{x := 1, x := 2};
  p := Point{1, 2};
  p := Point{x := TRUE};
  v := Vector{1, 2, 3, 4};
  v := Vector{x := 1};
  ptr := P{};
  v := Vector{{1}};
  p := Point{x := {1, 2}};
  o := lib.Open{a := 1};
  h := lib.Hidden{a := 1};
  r := lib.ReadOnly{a := 1};
  s := lib.Sub{c := 1};
  w := lib.Wrap{n := 1, h := h};
  w := lib.Wrap{h := {a := 1}};
  Change(Point{x := 1});
  p := i{};
  p := Point{x := 1 .. 3};
  v := Vector{1, 2 .. 3}
END Bad.
