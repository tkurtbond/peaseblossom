MODULE ErrBasics;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 8): rtl/vax's Err writes to SYS$ERROR what rtl/llvm's
     writes to the standard error, a record for each Ln. The last line is
     not ended by Ln: on VAX/VMS the exit handler writes it. *)
  IMPORT Err;
BEGIN
  Err.Open;
  Err.String("Err writes to the error stream"); Err.Ln;
  Err.Char("["); Err.Int(-42, 6); Err.Char("|"); Err.Int(7, 0); Err.Char("|");
  Err.Hex(255, 4); Err.Char("|"); Err.Hex(-1, 2); Err.Char("]"); Err.Ln;
  Err.Int(MIN(HUGEINT), 0); Err.Ln;
  Err.Flush;
  Err.String("not ended by Ln")
END ErrBasics.
