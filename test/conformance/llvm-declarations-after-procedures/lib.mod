MODULE lib;
  (* Exports declared after a procedure (doc/language-extensions.md,
     "Declarations after procedures") reach an importer through the .sym
     file like any others. *)
  VAR calls*: INTEGER;

  PROCEDURE Count*; BEGIN INC(calls) END Count;

  CONST limit* = 3;
  TYPE Pair* = RECORD a*, b*: INTEGER END;
  VAR last*: Pair;

  PROCEDURE Set*(a, b: INTEGER); BEGIN last.a := a; last.b := b; Count END Set;
END lib.
