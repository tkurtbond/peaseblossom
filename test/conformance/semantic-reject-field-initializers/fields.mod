MODULE Fields;
  TYPE
    A = RECORD x: INTEGER := later END;
    B = RECORD s: INTEGER := "abc"; t, u: BOOLEAN := 1 END;
    C = RECORD c: INTEGER := Late() END;
  VAR later: INTEGER;
  PROCEDURE Late(): INTEGER; BEGIN RETURN 1 END Late;
  PROCEDURE P(q: INTEGER);
    CONST c = 4;
    VAR v: INTEGER;
    PROCEDURE Inner(): INTEGER; BEGIN RETURN 2 END Inner;
    TYPE L = RECORD a: INTEGER := c; b: INTEGER := v; d: INTEGER := q; e: INTEGER := Inner() END;
  BEGIN
  END P;
END Fields.
