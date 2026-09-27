MODULE ParamNames;
(* Parameters named like the LLVM backend's own names in a function - its
   labels (entry, L1), temporaries (t1) and hidden parameters (up, p, self) -
   each kind of parameter: value, VAR, VAR record (a hidden tag), open array
   (hidden lengths), a receiver, and one a nested procedure uses
   (Phase 11 D18). *)
IMPORT Out;

TYPE
  R = RECORD n: INTEGER END;
  P = POINTER TO RECORD (R) END;

PROCEDURE Sum(entry, L1, L2, t1, t2: INTEGER; up, p, self: LONGINT): LONGINT;
  VAR s: LONGINT;
BEGIN
  IF entry > 0 THEN s := entry + L1 ELSE s := L2 END;
  WHILE t1 > 0 DO s := s + t2; DEC(t1) END;
  RETURN s + up + p + self
END Sum;

PROCEDURE Bump(VAR entry: INTEGER; VAR t1: R; VAR L1: ARRAY OF CHAR);
BEGIN
  INC(entry); INC(t1.n, entry); L1[0] := "X"
END Bump;

PROCEDURE (entry: P) Twice(t1: INTEGER): INTEGER;
BEGIN
  RETURN entry.n * 2 + t1
END Twice;

PROCEDURE Outer(t1: INTEGER; VAR L1: ARRAY OF CHAR): INTEGER;
  PROCEDURE Inner(entry: INTEGER): INTEGER;
  BEGIN
    RETURN t1 + entry + SHORT(LEN(L1))
  END Inner;
BEGIN
  RETURN Inner(100)
END Outer;

VAR i: INTEGER; r: R; q: P; s: ARRAY 8 OF CHAR;

BEGIN
  Out.Int(Sum(1, 2, 3, 4, 5, 6, 7, 8), 0); Out.Ln;
  i := 10; r.n := 1; s := "abc";
  Bump(i, r, s);
  Out.Int(i, 0); Out.Char(" "); Out.Int(r.n, 0); Out.Char(" "); Out.String(s); Out.Ln;
  NEW(q); q.n := 21;
  Out.Int(q.Twice(3), 0); Out.Ln;
  Out.Int(Outer(5, s), 0); Out.Ln
END ParamNames.
