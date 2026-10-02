MODULE target;
(* A type guard as the last selector of an assignment's target, v(T) := e
   (Oberon2.pdf 8.1, 9.1): a pointer variable, p(Q) := q and p(Q)^ := t;
   a VAR record parameter, x(S) := y; and a pointer reached through a
   record field or an array element, bp.f(Q) := q, a[1](Q)^ := t (a
   pointer cannot point to a pointer, 6.4).  The last statement's guard
   fails (status 5).  It was a syntax error until 2026-10-02
   (000-todo.org). *)
IMPORT Out;
TYPE
  R = RECORD a: INTEGER END;
  S = RECORD (R) b: INTEGER END;
  P = POINTER TO R;
  Q = POINTER TO S;
  Box = RECORD f: P END;
  BoxPointer = POINTER TO Box;
VAR p: P; q, q2: Q; t: S; v: R; bp: BoxPointer; a: ARRAY 2 OF P;

PROCEDURE Set(VAR x: R; VAR y: S);
BEGIN x(S) := y
END Set;

BEGIN
  NEW(q); p := q; t.a := 1; t.b := 2;
  p(Q)^ := t; Out.Int(q.a, 0); Out.Int(q.b, 2); Out.Ln;
  t.a := 5; t.b := 6; Set(q^, t); Out.Int(q.a, 0); Out.Int(q.b, 2); Out.Ln;
  NEW(q2); q2.b := 7; p(Q) := q2; Out.Int(p(Q).b, 0); Out.Ln;
  NEW(bp); bp.f := q; t.b := 8; bp.f(Q)^ := t; Out.Int(q.b, 0); Out.Ln;
  bp.f(Q) := q2; Out.Int(bp.f(Q).b, 0); Out.Ln;
  bp^.f(Q) := q; Out.Int(bp^.f(Q).b, 0); Out.Ln;
  a[1] := q; t.b := 9; a[1](Q)^ := t; Out.Int(q.b, 0); Out.Ln;
  a[1](Q) := q2; Out.Int(a[1](Q).b, 0); Out.Ln;
  NEW(a[0]); a[0](Q) := q
END target.
