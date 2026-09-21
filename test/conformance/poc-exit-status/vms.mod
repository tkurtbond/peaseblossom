MODULE vms;
  VAR g: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE ["VMS", "sys$foo"] Foo(x: INTEGER);
BEGIN
  g := 0; Foo(g);
  IF g = 0 THEN SysWrite(1, "ok", 2) ELSE SysWrite(1, "WRONG", 5) END
END vms.
