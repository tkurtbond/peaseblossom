MODULE predeclared;
  (* PLAN.md Phase 8 step 11's dedicated compile+link+run+diff-stdout
     fixture for the in-scope predeclared-procedure subset: ABS, ODD,
     CHR, ORD, CAP, LEN (both the one- and two-argument forms), INC,
     DEC, and COPY. NEW/DISPOSE and anything SYSTEM.* are out of scope
     (Phase 9, they presuppose POINTER); HALT is deliberately NOT
     exercised here since it terminates the process before this
     fixture's own "OK"/"FAIL" write - see llvm-predeclared-halt for
     HALT's own dedicated exit-code fixture instead.

     Two things intentionally routed around here, both real Oberon-2
     but genuine, pre-existing, out-of-scope gaps unrelated to this
     step's own predeclared-procedure codegen (found while developing
     this fixture, not introduced by it):
       - a single-char STRING literal used as a plain CHAR value
         outside a call argument or ORD's own special-cased argument
         position (e.g. "a CHAR variable := <string literal>", or
         "<CHAR value> = <string literal>" in a general expression) -
         GenerateExpr has no general string-literal-to-CHAR conversion,
         only ORD's own codegen intercepts that one shape directly.
         Worked around below by using hex CHAR literals (nnX) for every
         CHAR value/comparison except ORD's own argument, which keeps
         exercising ORD's dedicated single-char-string-literal path.
         (Resolved by PLAN.md Phase 9 step 3: a one-character string in a
         scalar position is now a CHAR immediate; this fixture keeps its
         hex literals rather than being rewritten.)
       - forwarding an ARRAY OF CHAR *value parameter* (as opposed to a
         literal) into another call's own ARRAY OF CHAR argument -
         GenerateStringArgValue only lowers a literal string constant
         (PLAN.md Phase 8 step 8+'s own documented scope); this
         fixture's SysWrite calls all pass literals directly rather
         than through an intermediate wrapper procedure. A related but
         distinct bug WAS found and fixed this step: that unsupported
         path used to splice its own diagnostic comment directly into
         a call's argument-list text, producing invalid IR whenever an
         unsupported string/VAR argument appeared inside a call (not
         just this one) - see GenerateStringArgValue/GenerateVarArg-
         Value's own comments. *)
  VAR
    v: ARRAY 5 OF INTEGER;
    m: ARRAY 3, 4 OF INTEGER;
    s: ARRAY 10 OF CHAR;
    absVal, ordVal: INTEGER;
    lenVal, dim0, dim1: LONGINT;
    oddVal: BOOLEAN;
    chrVal, capVal, lowerCh: CHAR;
    i: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  absVal := ABS(-7);
  oddVal := ODD(5);
  chrVal := CHR(65);
  ordVal := ORD("Z");
  lowerCh := 71X;
  capVal := CAP(lowerCh);
  lenVal := LEN(v);
  dim0 := LEN(m, 0);
  dim1 := LEN(m, 1);
  i := 3;
  INC(i);
  INC(i, 10);
  DEC(i, 4);
  COPY("hi", s);

  IF (absVal = 7) & oddVal & (chrVal = 41X) & (ordVal = 90) & (capVal = 51X) &
     (lenVal = 5) & (dim0 = 3) & (dim1 = 4) & (i = 10) &
     (s[0] = 68X) & (s[1] = 69X) & (s[2] = 0X) THEN
    SysWrite(1, "OK", 2)
  ELSE
    SysWrite(1, "FAIL", 4)
  END
END predeclared.
