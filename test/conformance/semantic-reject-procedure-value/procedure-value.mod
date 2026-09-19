MODULE procedureValue;
  (* Oberon2.pdf 6.5: a procedure assigned to a procedure variable "must
     not be a predeclared or type-bound procedure nor may it be local to
     another procedure", and its parameter list must match the variable's
     type. poc also refuses an external one (it is called with the C
     convention, a procedure value with the Oberon one). A procedure's name
     is no operand of a comparison either - only a procedure-typed value
     (or NIL) is. Every use below is an error except the last three
     statements, which are the ordinary legal forms. voc rejects all of
     them but the external one, which it has no notion of: "procedure must
     have level 0", "'(' missing" (type-bound, predeclared), "number of
     parameters doesn't match", "this expression cannot be a type or a
     procedure" (a comparison). *)

  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Obj = POINTER TO ObjDesc;
    ObjDesc = RECORD END;
  VAR
    f, g: Binary; o: Obj; b: BOOLEAN;

  PROCEDURE ["C", "abs"] Absolute(a, b: INTEGER): INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

  PROCEDURE Unary(a: INTEGER): INTEGER;
  BEGIN RETURN a END Unary;

  PROCEDURE (o: Obj) Method(a, b: INTEGER): INTEGER;
  BEGIN RETURN a END Method;

  PROCEDURE Outer;
    PROCEDURE Inner(a, b: INTEGER): INTEGER;
    BEGIN RETURN a END Inner;
  BEGIN
    f := Inner
  END Outer;

BEGIN
  f := Absolute;
  f := o.Method;
  f := ABS;
  f := Unary;
  b := f = Add;
  b := Add # f;
  f := Add;
  g := f;
  b := (f = g) OR (g # NIL)
END procedureValue.
