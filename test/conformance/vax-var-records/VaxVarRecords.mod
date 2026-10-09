MODULE VaxVarRecords;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 5): a VAR record parameter takes its actual's type tag after
     its address - a variable's, a field's or an element's static
     descriptor, a heap block's tag for p^, a VAR parameter's own when it
     is passed on, an imported record's descriptor - and records holding
     pointers, with their descriptors. The debugger runs examine what it
     computes, and the tags Twice, Grow and VaxRecLib.Count receive. *)
  IMPORT L := VaxRecLib;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Box = RECORD lo, hi: Point; owner: L.Node END;
    PP = POINTER TO Point;
  VAR
    p, q: Point; b: Box; boxes: ARRAY 2 OF Box; pp: PP; pair: L.Pair; i, count: INTEGER;

  PROCEDURE Move(VAR pt: Point; dx: INTEGER);
  BEGIN
    pt.x := pt.x + dx; pt.y := pt.y - dx
  END Move;

  (* pt's own tag passed on *)
  PROCEDURE Twice(VAR pt: Point);
  BEGIN
    Move(pt, pt.x)
  END Twice;

  PROCEDURE Grow(n: INTEGER; VAR bx: Box; VAR again: Point);
  BEGIN
    Move(bx.lo, -n); Move(bx.hi, n);
    NEW(bx.owner); bx.owner.v := n;
    Move(again, 1)
  END Grow;

BEGIN
  Move(p, 3); Twice(p);
  Grow(2, b, p);
  i := 1; boxes[i] := b; Grow(5, boxes[i], boxes[0].hi);
  NEW(pp); Move(pp^, 4); Twice(pp^); q := pp^;
  pair.a := b.owner; pair.b := boxes[1].owner; pair.n := 10;
  count := L.Count(pair)
END VaxVarRecords.
