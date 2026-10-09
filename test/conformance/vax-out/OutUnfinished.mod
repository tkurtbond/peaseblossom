MODULE OutUnfinished;
  (* PLAN.md Phase 16 step 3: a line the program does not end with Ln is
     written still when it ends, on VAX/VMS by the exit handler that Out's
     body has the runtime declare (POC_OUT_REGISTER), as a record of its
     own *)
  IMPORT Out;
BEGIN
  Out.String("ended by "); Out.String("the exit handler")
END OutUnfinished.
