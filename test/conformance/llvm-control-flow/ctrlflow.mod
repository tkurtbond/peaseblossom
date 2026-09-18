MODULE ctrlflow;
  (* PLAN.md Phase 8 step 7's own compile+link+run+diff-stdout fixture:
     exercises IF/ELSIF/ELSE, CASE (over both INTEGER and CHAR, including
     a range label), WHILE, REPEAT, FOR (both ascending and descending,
     the latter exercising a negative BY step), and LOOP+EXIT, using
     step 6's write(2) FFI to print a one-letter marker for whichever
     branch/iteration actually ran - real runtime behavior, not just a
     golden-diffed .ll (see llvm-control-flow-ir for that style, covering
     the same constructs from the other direction). No marker is
     separated by a newline: Oberon-2 string literals have no backslash-
     escape syntax and can't span a line, so there is no way to embed a
     literal 0AX byte inside one - the whole expected output is simply
     one unbroken line of markers instead. RETURN itself has no
     dedicated marker here - a bare RETURN's only observable effect,
     early module-body termination, isn't distinguishable from "ran to
     completion" without one more marker after it, and step 7's own
     RETURN scope is just "ret void" (no function procedures exist yet
     to return a value from - see LLVMCodeGenerator.GenerateReturnStatement's
     own header comment); exercised directly via -emit-llvm-ir inspection
     during development instead. *)
  VAR i, n: INTEGER; ch: CHAR;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  n := 7;
  IF n < 5 THEN SysWrite(1, "A", 1)
  ELSIF n < 10 THEN SysWrite(1, "B", 1)
  ELSE SysWrite(1, "C", 1)
  END;

  CASE n OF
    1, 2: SysWrite(1, "P", 1)
  | 5..9: SysWrite(1, "Q", 1)
  ELSE SysWrite(1, "S", 1)
  END;

  ch := 5AX;
  CASE ch OF
    41X..5AX: SysWrite(1, "T", 1)
  ELSE SysWrite(1, "U", 1)
  END;

  i := 0;
  WHILE i < 3 DO
    SysWrite(1, "W", 1);
    i := i + 1
  END;

  i := 0;
  REPEAT
    SysWrite(1, "X", 1);
    i := i + 1
  UNTIL i >= 2;

  FOR i := 1 TO 3 DO SysWrite(1, "Y", 1) END;
  FOR i := 3 TO 1 BY -1 DO SysWrite(1, "Z", 1) END;

  i := 0;
  LOOP
    IF i >= 2 THEN EXIT END;
    SysWrite(1, "M", 1);
    i := i + 1
  END
END ctrlflow.
