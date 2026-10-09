MODULE VaxModLib;
  (* Imported by VaxModules: exported constants, types, variables and
     procedures. It imports VaxModBase under another name. *)

  IMPORT B := VaxModBase;

  CONST Limit* = 10; Greeting* = "hello";

  TYPE
    Point* = RECORD x*, y*: INTEGER END;
    Table* = ARRAY 4 OF INTEGER;

  VAR count*: LONGINT; table*: Table; origin*: Point;

  PROCEDURE Add*(n: LONGINT);
  BEGIN INC(count, n)
  END Add;

  PROCEDURE Twice*(x: INTEGER): INTEGER;
  BEGIN RETURN 2 * x
  END Twice;

  PROCEDURE Total*(t: Table): LONGINT;
    VAR i: INTEGER; sum: LONGINT;
  BEGIN
    sum := 0;
    FOR i := 0 TO LEN(t) - 1 DO sum := sum + t[i] END;
    RETURN sum
  END Total;

  PROCEDURE Move*(VAR p: Point; dx: INTEGER);
  BEGIN INC(p.x, dx)
  END Move;

BEGIN
  B.Note(2); count := 100; table[2] := 7; origin.y := -1
END VaxModLib.
