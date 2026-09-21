MODULE nestedorder;
  (* The order of a needs list is the declaration order, outermost declaring
     procedure first - not the order the body happens to mention them in. *)

  PROCEDURE Root;
    VAR c, a: INTEGER;

    PROCEDURE Mid;
      VAR b, d: INTEGER;

      PROCEDURE Leaf;
      BEGIN
        d := a + b + c
      END Leaf;

    BEGIN
      Leaf
    END Mid;

  BEGIN
    Mid
  END Root;

BEGIN
END nestedorder.
