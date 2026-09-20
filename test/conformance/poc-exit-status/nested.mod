MODULE nested;
  VAR g: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE Outer;
    VAR local: INTEGER;
    PROCEDURE Inner;
    BEGIN g := g + 1
    END Inner;
    PROCEDURE UsesLocal;
    BEGIN local := local + 10
    END UsesLocal;
  BEGIN
    local := 5;
    Inner; Inner;
    UsesLocal;
    g := g + local
  END Outer;
BEGIN
  g := 0; Outer;
  IF g = 17 THEN SysWrite(1, "ok", 2) ELSE SysWrite(1, "WRONG", 5) END
END nested.
