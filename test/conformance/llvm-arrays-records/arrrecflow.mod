MODULE arrrecflow;
  (* PLAN.md Phase 8 step 8's own compile+link+run+diff-stdout fixture:
     exercises fixed-size ARRAY/RECORD element/field read and write
     (via getelementptr, LLVMCodeGenerator.GenerateDesignatorAddress)
     and whole-value ARRAY/RECORD assignment (a plain "load [N x T]"/
     "store [N x T]" of the aggregate type, needing no dedicated
     codegen of its own - already generic in LoadVar/StoreIntoVar since
     step 5). Values are proven correct the same way step 7's own
     llvm-control-flow fixture proved control flow: IF branches on a
     computed array/record result and prints one of two literal
     markers, since this step's FFI still only accepts a literal STRING
     constant as an ARRAY OF CHAR argument (a computed CHAR array/field
     value can't be printed directly yet) - see
     llvm-arrays-records-ir for the same constructs verified by
     directly inspecting computed values instead, via the C-harness
     technique. *)
  TYPE
    Point = RECORD x, y: INTEGER END;
    Vec3 = ARRAY 3 OF INTEGER;
  VAR
    v: Vec3;
    p, p2: Point;
    sum: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  v[0] := 10; v[1] := 20; v[2] := 30;
  sum := v[0] + v[1] + v[2];
  IF sum = 60 THEN SysWrite(1, "A", 1) ELSE SysWrite(1, "a", 1) END;

  p.x := 5; p.y := 7;
  p2 := p;
  p2.x := 100;
  IF (p.x = 5) & (p2.x = 100) THEN SysWrite(1, "B", 1) ELSE SysWrite(1, "b", 1) END;

  v[1] := p2.x - p.x;
  IF v[1] = 95 THEN SysWrite(1, "C", 1) ELSE SysWrite(1, "c", 1) END
END arrrecflow.
