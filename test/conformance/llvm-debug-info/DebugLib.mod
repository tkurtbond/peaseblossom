MODULE DebugLib;
(* Phase 11 A16: an imported module with a procedure and a type-bound one,
   for llvm-debug-info's breakpoints and backtraces. *)

TYPE
  Counter* = POINTER TO CounterDesc;
  CounterDesc* = RECORD n*: INTEGER END;

PROCEDURE Square*(x: INTEGER): INTEGER;
  VAR y: INTEGER;
BEGIN
  y := x * x;
  RETURN y
END Square;

PROCEDURE (c: Counter) Add*(k: INTEGER);
BEGIN
  c.n := c.n + Square(k)
END Add;

END DebugLib.
