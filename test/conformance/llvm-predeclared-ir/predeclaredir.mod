MODULE predeclaredir;
  (* PLAN.md Phase 8 step 11's dedicated golden-file fixture for the
     same 9 predeclared procedures llvm-predeclared exercises at
     runtime (everything but HALT, see llvm-predeclared-halt), verified
     by directly inspecting the computed values instead of branching on
     them - see llvm-procedures-ir for the same "branch vs. inspect"
     split applied to ordinary-procedure codegen. This fixture's own
     final values were independently verified during development:
     absVal=7, oddVal=TRUE(1), chrVal='A'(65), ordVal=90, capVal='Q'(81),
     lenVal=5, dim0=3, dim1=4, i=10, s="hi". *)
  VAR
    v: ARRAY 5 OF INTEGER;
    m: ARRAY 3, 4 OF INTEGER;
    s: ARRAY 10 OF CHAR;
    absVal, ordVal: INTEGER;
    lenVal, dim0, dim1: LONGINT;
    oddVal: BOOLEAN;
    chrVal, capVal, lowerCh: CHAR;
    i: INTEGER;
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
  COPY("hi", s)
END predeclaredir.
