MODULE Stacks;
  IMPORT Lists;
  TYPE Stack* = RECORD (Lists.Node) depth*: INTEGER END;
  PROCEDURE Fill*(VAR l: Lists.List; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 1 TO n DO Lists.Push(l, i) END
  END Fill;
END Stacks.
