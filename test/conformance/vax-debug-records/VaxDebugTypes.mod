MODULE VaxDebugTypes;
  (* PLAN.md Phase 18 step 5d: the debugger's records of the structured
     types (doc/developer/vax-object-language.md, section 16.8): records,
     one extending another, a record with a pointer to its own type, two
     records pointing to each other, fixed arrays of basic types, of
     BOOLEAN, of records, of two dimensions, a pointer to an array, a
     procedure variable, sets, and open array parameters of one and two
     dimensions, each shown in the VMS debugger. The pointers point to
     module variables, so that it needs no collector *)
  IMPORT SYSTEM;

  TYPE
    Point = RECORD x, y: INTEGER; c: CHAR END;
    Point3 = RECORD (Point) z: LONGINT END;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD key: INTEGER; next: Node END;
    Vector = ARRAY 5 OF INTEGER;
    Grid = ARRAY 3, 4 OF SHORTINT;
    Action = PROCEDURE (x: INTEGER): INTEGER;
    Segment = RECORD a, b: Point; tag: ARRAY 8 OF CHAR END;
    PA = POINTER TO A;
    PB = POINTER TO B;
    PVector = POINTER TO Vector;
    A = RECORD toB: PB; v: INTEGER END;
    B = RECORD toA: PA; w: INTEGER END;

  VAR
    p: Point; p3: Point3; head: Node; v: Vector; g: Grid; act: Action;
    s: SET; s64: SYSTEM.SET64; f: ARRAY 3 OF BOOLEAN; seg: Segment;
    pts: ARRAY 2 OF Point; ra: PA; pv: PVector;
    names: ARRAY 2, 4 OF CHAR; sum: LONGINT;
    n1, n2: NodeDesc; a1: A; b1: B; v1: Vector;

  PROCEDURE Twice(x: INTEGER): INTEGER;
  BEGIN
    RETURN 2 * x
  END Twice;

  PROCEDURE Total(VAR w: Vector; a: ARRAY OF INTEGER; VAR q: Point; m: ARRAY OF ARRAY OF CHAR): LONGINT;
    VAR local: Point; i: INTEGER; t: LONGINT;
  BEGIN
    local := q; t := 0;
    FOR i := 0 TO SHORT(LEN(a)) - 1 DO t := t + a[i] END;
    FOR i := 0 TO 4 DO t := t + w[i] END;
    t := t + local.x + ORD(m[1, 0]);
    RETURN t
  END Total;

  PROCEDURE Fill;
    VAR i, j: INTEGER;
  BEGIN
    p.x := 1; p.y := 2; p.c := "p";
    p3.x := 3; p3.y := 4; p3.c := "3"; p3.z := 100000;
    head := SYSTEM.VAL(Node, SYSTEM.ADR(n1)); head.key := 7;
    head.next := SYSTEM.VAL(Node, SYSTEM.ADR(n2)); head.next.key := 8;
    FOR i := 0 TO 4 DO v[i] := 10 * (i + 1) END;
    FOR i := 0 TO 2 DO FOR j := 0 TO 3 DO g[i, j] := SHORT(10 * i + j) END END;
    act := Twice;
    s := {0, 3, 31}; s64 := {1, 40};
    f[0] := TRUE; f[1] := FALSE; f[2] := TRUE;
    seg.a := p; seg.b.x := 5; seg.b.y := 6; seg.b.c := "b"; seg.tag := "segment";
    pts[0] := p; pts[1].x := 9; pts[1].y := 10; pts[1].c := "z";
    ra := SYSTEM.VAL(PA, SYSTEM.ADR(a1)); ra.toB := SYSTEM.VAL(PB, SYSTEM.ADR(b1));
    ra.v := 11; ra.toB.w := 12; ra.toB.toA := ra;
    pv := SYSTEM.VAL(PVector, SYSTEM.ADR(v1)); pv^ := v;
    names[0] := "abc"; names[1] := "xyz"
  END Fill;

BEGIN
  Fill;
  sum := Total(v, v, p, names) + act(3)
END VaxDebugTypes.
