MODULE client;
  (* CONST, TYPE and VAR sections after and between procedures, at module
     level and inside a procedure; each procedure uses only what is
     declared above it. *)
  IMPORT Out, L := lib;
  VAR count: INTEGER;

  PROCEDURE Bump; BEGIN INC(count) END Bump;

  CONST step = 10;
  TYPE Point = RECORD x, y: INTEGER END;
  VAR origin: Point;

  PROCEDURE Move(VAR p: Point);
    VAR dx: INTEGER;
    PROCEDURE Twice(n: INTEGER): INTEGER; BEGIN RETURN 2 * n END Twice;
    CONST dy = 3;
    VAR total: INTEGER;
  BEGIN dx := Twice(step); p.x := p.x + dx; p.y := p.y + dy; total := p.x + p.y;
    Out.Int(total, 0); Out.Ln
  END Move;

  TYPE List = POINTER TO Node;
    Node = RECORD val: INTEGER; next: List END;
  VAR head: List; q: L.Pair; i: INTEGER;
BEGIN
  Bump; Bump; Move(origin); NEW(head); head.val := count;
  Out.Int(count, 0); Out.Char(" "); Out.Int(origin.x, 0); Out.Char(" ");
  Out.Int(origin.y, 0); Out.Char(" "); Out.Int(head.val, 0); Out.Ln;
  FOR i := 1 TO L.limit DO L.Set(i, 10 * i) END;
  q := L.last;
  Out.Int(L.calls, 0); Out.Char(" "); Out.Int(q.a, 0); Out.Char(" "); Out.Int(q.b, 0); Out.Ln
END client.
