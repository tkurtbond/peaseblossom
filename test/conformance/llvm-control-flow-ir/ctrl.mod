MODULE ctrl;
  (* PLAN.md Phase 8 step 7's dedicated golden-file fixture for real
     control-flow codegen: IF/ELSIF/ELSE, CASE (over INTEGER with both a
     single-value and a range label, and separately over CHAR with a
     range label), WHILE, REPEAT, FOR (both ascending and a descending
     negative-BY-step form), and LOOP+EXIT - see llvm-control-flow for
     the same constructs exercised the other way, at runtime through the
     step 6 write(2) FFI. A pure -emit-llvm-ir golden diff, not a
     compile+link+run fixture (nothing here calls out to any FFI to
     observe) - this fixture's own computed values were independently
     verified during development by linking the generated .ll (its own
     auto-generated @main stripped) against a small hand-written C
     harness that asm-renamed each extern to its real, dotted LLVM
     global name (e.g. `extern int16_t ctrl_ifResult __asm__(
     "ctrl.ifResult");` - a "." is a valid unquoted LLVM identifier
     character but not a valid C one) and printf'd every global after
     calling ctrl_init(), confirmed correct by hand:
     ifResult=2 caseResult1=20 caseResult2=1 caseResult3=99
     whileSum=12 repeatSum=10 forSum=30 loopCount=7 - not by inspection
     of the IR alone. *)
  VAR
    ifResult, caseResult1, caseResult2, caseResult3, whileSum, repeatSum, forSum, loopCount, i: INTEGER;
    ch: CHAR;
BEGIN
  IF 5 > 10 THEN ifResult := 1
  ELSIF 5 = 5 THEN ifResult := 2
  ELSE ifResult := 3
  END;

  caseResult1 := 0;
  CASE 4 OF
    1, 2: caseResult1 := 10
  | 3..5: caseResult1 := 20
  ELSE caseResult1 := 30
  END;

  ch := 42X;
  CASE ch OF
    41X..5AX: caseResult2 := 1
  ELSE caseResult2 := 2
  END;

  CASE 99 OF
    1: caseResult3 := 1
  ELSE caseResult3 := 99
  END;

  whileSum := 0;
  WHILE whileSum < 10 DO whileSum := whileSum + 3 END;

  repeatSum := 0;
  REPEAT repeatSum := repeatSum + 2 UNTIL repeatSum >= 9;

  forSum := 0;
  FOR i := 1 TO 5 DO forSum := forSum + i END;
  FOR i := 5 TO 1 BY -1 DO forSum := forSum + i END;

  loopCount := 0;
  LOOP
    loopCount := loopCount + 1;
    IF loopCount >= 7 THEN EXIT END
  END
END ctrl.
