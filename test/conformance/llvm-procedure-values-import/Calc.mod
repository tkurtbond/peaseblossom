MODULE Calc;
  (* The library half of llvm-procedure-values-import: exported procedures
     to be used as values by another module, a procedure type and a
     procedure-typed variable of its own, and a procedure taking one. *)
  TYPE
    Op* = PROCEDURE (a, b: INTEGER): INTEGER;
    Table* = RECORD add*, mul*: Op END;
  VAR
    current*: Op;
    table*: Table;

  PROCEDURE Add*(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

  PROCEDURE Mul*(a, b: INTEGER): INTEGER;
  BEGIN RETURN a * b END Mul;

  PROCEDURE Apply*(op: Op; a, b: INTEGER): INTEGER;
  BEGIN RETURN op(a, b) END Apply;

  PROCEDURE Use*(op: Op);
  BEGIN current := op END Use;

  PROCEDURE Call*(a, b: INTEGER): INTEGER;
  BEGIN RETURN current(a, b) END Call;

BEGIN
  current := Add;
  table.add := Add;
  table.mul := Mul
END Calc.
