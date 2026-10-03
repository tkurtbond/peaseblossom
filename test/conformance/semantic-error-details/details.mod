MODULE details;
  (* Phase 13 step 2: a compile error names the identifier or the types it
     is about, "message: details" *)
  IMPORT lib;
  TYPE Node = POINTER TO NodeDesc; NodeDesc = RECORD next: Node END;
    P = POINTER TO RECORD x: INTEGER END;
  VAR i: INTEGER; c: CHAR; n: Node; p: P; a: ARRAY 4 OF CHAR; s: SET; b: BOOLEAN;
    r: lib.Rider;
  PROCEDURE V(VAR x: INTEGER); END V;
  PROCEDURE W(x: ARRAY OF INTEGER); BEGIN i := x END W;
BEGIN
  Ot.String("x"); lib.cont := 1; lib.secret := 1; r.hidden := 1; i := c; n := p; p := n; V(c); a := n;
  b := s < i; i := b + s; i(); i := zz; n.foo := 1; FOR k := 1 TO 2 DO END;
  i := r; r := s; i := "abc"; b := (i = c); i := c MOD 2; b := s IN b;
  i := lib; i := Node; i := details.c;
  b := ODD(1.5); i := ORD(1.0); INC(c); NEW(i); i := LEN(n)
END details.
