MODULE readonlyParam;
  (* doc/developer/language-extensions.md, "Read-only parameters": nothing may
     assign to x- or any part of it, or pass it or any part of it as a
     VAR argument or a VAR receiver *)
  IMPORT Shared;
  TYPE
    R = RECORD x: INTEGER; a: ARRAY 4 OF INTEGER END;
    P = POINTER TO R;
  PROCEDURE (VAR r: R) Set; BEGIN r.x := 1 END Set;
  PROCEDURE (p: P) Clear; BEGIN p.x := 0 END Clear;
  PROCEDURE V(VAR i: INTEGER); BEGIN END V;
  PROCEDURE W(i-: INTEGER); BEGIN END W;
  PROCEDURE Value(i: INTEGER); BEGIN END Value;
  PROCEDURE Q(r-: R; i-: INTEGER; s-: ARRAY OF CHAR; p-: P);
  BEGIN
    r.x := 1; r.a[0] := 2; i := 3; s[0] := "x";
    INC(i); COPY("y", s);
    V(i); V(r.a[1]);
    r.Set;
    p := NIL;
    (* allowed: reading it, passing it on by value or read-only, and
       writing through a pointer it holds *)
    W(i); Value(i); W(r.a[2]); p^.x := 4; p.x := 5; p.Clear
  END Q;
BEGIN
  (* an imported read-only variable is no VAR argument either (voc: err 76),
     nor a VAR receiver *)
  V(Shared.v); Shared.r.Bump
END readonlyParam.
