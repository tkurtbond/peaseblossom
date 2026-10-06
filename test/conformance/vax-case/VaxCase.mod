MODULE VaxCase;
  (* PLAN.md Phase 15 step 4: CASE. Dense labels use CASEx, its table
     pointing at a JMP L^ to each arm; sparse ones a compare for each
     label. A value with no label and no ELSE calls POC_TRAP with the
     trap's code (3, as on LLVM), the module's name and the position
     (decided with the user 2026-10-06) *)

  VAR i, j: INTEGER; c: CHAR; l: LONGINT;

BEGIN
  CASE i OF
    1: j := 1
  | 2, 3: j := 2
  | 4 .. 6: j := 3
  END;
  CASE c OF
    "a" .. "e", "x": i := 1
  | "f", "g": i := 2
  ELSE i := 0
  END;
  CASE l OF
    1000: i := 1
  | 2000 .. 2005: i := 2
  ELSE
  END
END VaxCase.
