MODULE nestedscopes;
  (* Names are resolved against the real scope chain: a module-level variable,
     a module-level procedure, a same-named local of the nested procedure
     itself, and a nested procedure that has the name of a module-level one
     are each what they are, whatever they are spelled like. *)
  VAR g: INTEGER;

  PROCEDURE Shared(k: INTEGER): INTEGER;
  BEGIN RETURN k + g
  END Shared;

  PROCEDURE A;
    VAR x: INTEGER;

    PROCEDURE Helper;
    BEGIN x := Shared(x)
    END Helper;

  BEGIN Helper
  END A;

  PROCEDURE B;
    VAR y: INTEGER;

    PROCEDURE Helper;
    BEGIN y := 1
    END Helper;

  BEGIN Helper
  END B;

  PROCEDURE C;
    VAR x: INTEGER;

    PROCEDURE Uses;
    BEGIN A
    END Uses;

    PROCEDURE Sibling;
      VAR x: INTEGER;
    BEGIN x := g
    END Sibling;

  BEGIN Uses; Sibling
  END C;

  PROCEDURE D;
    VAR q: INTEGER;

    PROCEDURE Shared;
    BEGIN q := 0
    END Shared;

    PROCEDURE Caller;
    BEGIN Shared
    END Caller;

  BEGIN Caller
  END D;

BEGIN
END nestedscopes.
