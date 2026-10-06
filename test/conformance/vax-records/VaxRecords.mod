MODULE VaxRecords;
  (* PLAN.md Phase 15 step 6: records, with no base type. A field is its
     offset in MemoryLayout's layout; reached through a parameter's address,
     @n(AP), the address is moved to a register first. A whole record is
     copied by MOVC3. A record value parameter is passed by its address
     and copied to the callee's frame on entry, unless it is read-only
     (decided with the user 2026-10-06); a VAR one is its address, with no
     type tag until Phase 16 brings extension. *)

  TYPE
    Point = RECORD x, y: INTEGER END;
    Shape = RECORD
      kind: CHAR;
      corner: Point;
      size: LONGINT;
      tags: ARRAY 3 OF CHAR;
      big: HUGEINT
    END;
  VAR
    p, r: Point;
    s: Shape;
    shapes: ARRAY 4 OF Shape;
    i: INTEGER; n: LONGINT; h: HUGEINT;

  PROCEDURE Move(VAR pt: Point; dx: INTEGER);
  BEGIN
    pt.x := pt.x + dx;
    pt.y := pt.y + dx
  END Move;

  PROCEDURE Area(sh: Shape): LONGINT;
  BEGIN
    sh.size := sh.size * 2;
    RETURN sh.size + sh.corner.x
  END Area;

  PROCEDURE Peek(sh-: Shape; k: INTEGER): CHAR;
  BEGIN
    RETURN sh.tags[k]
  END Peek;

  PROCEDURE First(VAR sh: Shape): CHAR;
  BEGIN
    RETURN sh.kind
  END First;

  PROCEDURE Local;
    VAR a, b: Point; t: Shape; c: CHAR;
  BEGIN
    a.x := 1; b := a; t.corner := b; c := t.kind;
    t.big := t.big + 1
  END Local;

BEGIN
  p.x := 3; p.y := p.x;
  r := p;
  s.corner := p;
  s.corner.y := 4;
  shapes[i].corner.x := 5;
  shapes[2] := s;
  shapes[i].tags[n] := "a";
  h := shapes[i].big;
  Move(p, 2);
  Move(shapes[i].corner, i);
  n := Area(s);
  n := Area(shapes[i]);
  s.kind := Peek(shapes[1], i);
  s.kind := First(shapes[i])
END VaxRecords.
