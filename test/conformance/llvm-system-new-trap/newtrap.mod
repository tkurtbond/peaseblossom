MODULE newtrap;
  (* PLAN.md Phase 10 step 7: SYSTEM.NEW of a block whose size is not
     positive is the length trap NEW(p, n) has (exit 7). *)
  IMPORT SYSTEM, Out;
  VAR any: SYSTEM.PTR; size: LONGINT;
BEGIN
  size := 16;
  SYSTEM.NEW(any, size);
  Out.String("a block of 16 bytes"); Out.Ln;
  size := 0;
  SYSTEM.NEW(any, size);
  Out.String("not reached"); Out.Ln
END newtrap.
