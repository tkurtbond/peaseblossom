MODULE Tally;
  (* The library half of llvm-nested-import: exported procedures (one
     type-bound) that use nested ones. None of the nested ones is exported,
     and none may show in Tally.sym. *)
  TYPE
    Counter* = RECORD count*: INTEGER END;

  VAR total*: INTEGER;

  PROCEDURE SumTo*(n: INTEGER): INTEGER;
    VAR t: INTEGER;
    PROCEDURE Add(k: INTEGER);
    BEGIN t := t + k; total := total + 1
    END Add;
    PROCEDURE Loop;
      VAR i: INTEGER;
    BEGIN
      FOR i := 1 TO n DO Add(i) END
    END Loop;
  BEGIN
    t := 0; Loop;
    RETURN t
  END SumTo;

  PROCEDURE (VAR c: Counter) Bump*(times: INTEGER);
    PROCEDURE One;
    BEGIN c.count := c.count + 1
    END One;
    PROCEDURE Many;
      VAR i: INTEGER;
    BEGIN
      FOR i := 1 TO times DO One END
    END Many;
  BEGIN
    Many
  END Bump;

  PROCEDURE Fill*(VAR a: ARRAY OF INTEGER);
    VAR i: INTEGER;
    PROCEDURE Set(i: INTEGER);
    BEGIN a[i] := i * i
    END Set;
  BEGIN
    FOR i := 0 TO SHORT(LEN(a)) - 1 DO Set(i) END
  END Fill;

BEGIN
  total := 0
END Tally.
