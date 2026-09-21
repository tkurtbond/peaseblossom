MODULE nestedbasic;
  CONST limit = 10;
  VAR global: INTEGER;

  PROCEDURE Outer(p: INTEGER; VAR q: INTEGER);
    VAR a, b, c: INTEGER;

    PROCEDURE UsesA;
    BEGIN a := a + 1
    END UsesA;

    PROCEDURE UsesParams;
    BEGIN q := p
    END UsesParams;

    PROCEDURE NothingLocal;
      VAR a: INTEGER; (* shadows Outer's a *)
    BEGIN a := 1; global := limit
    END NothingLocal;

    PROCEDURE Middle;
      VAR m: INTEGER;

      PROCEDURE Deep;
      BEGIN b := m + 1
      END Deep;

    BEGIN Deep
    END Middle;

    PROCEDURE CallsUsesA;
    BEGIN UsesA
    END CallsUsesA;

  BEGIN
    UsesA; UsesParams; NothingLocal; Middle; CallsUsesA
  END Outer;

BEGIN
END nestedbasic.
