MODULE DebugLib;
(* Phase 11 A16: an imported module with a procedure and a type-bound one,
   for llvm-debug-info's breakpoints, backtraces and variables. *)

TYPE
  Counter* = POINTER TO CounterDesc;
  CounterDesc* = RECORD n*: INTEGER END;
  Named* = RECORD (CounterDesc) name*: ARRAY 8 OF CHAR; scores*: ARRAY 3 OF LONGINT END;

VAR total: INTEGER; last: Named;

PROCEDURE Square*(x: INTEGER): INTEGER;
  VAR y: INTEGER; odd: BOOLEAN; half: REAL;
BEGIN
  y := x * x;
  odd := ODD(x); half := x / 2;
  RETURN y
END Square;

PROCEDURE (c: Counter) Add*(k: INTEGER);
BEGIN
  c.n := c.n + Square(k); INC(total)
END Add;

PROCEDURE Keep*(c: Counter; VAR r: Named);
BEGIN
  r.n := c.n; r.name := "sum"; r.scores[1] := c.n * 2;
  last := r
END Keep;

END DebugLib.
