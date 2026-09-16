MODULE forwardMismatch;
  (* Oberon2.pdf §10: "the formal parameter lists of the forward
     declaration and the actual declaration must be identical" - here
     the actual declaration adds a second parameter. *)

  PROCEDURE ^ Foo(x: INTEGER);

  PROCEDURE Foo(x, y: INTEGER);
  BEGIN
  END Foo;

BEGIN
END forwardMismatch.
