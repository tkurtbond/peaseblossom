MODULE predhalt;
  (* PLAN.md Phase 8 step 11's dedicated fixture for HALT: unlike the
     other 9 in-scope predeclared procedures (see llvm-predeclared),
     HALT terminates the process immediately (GenerateHalt emits
     "call void @exit(i32 <n>)" then "unreachable", reusing @exit -
     already unconditionally declared by step 9's EmitRuntimeSupport,
     the same runtime support routine the index-range/CASE traps
     themselves call) - so it needs its own exit-status fixture rather
     than an "OK"/"FAIL" stdout diff, the same way the index-range and
     CASE traps do (see llvm-index-range-trap/llvm-case-trap), not
     poc_build_run's plumbing. The statement after HALT(3) is real,
     front-end-accepted, but genuinely dead code - proving it is never
     reached is exactly the point of this fixture. *)
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "before", 6);
  HALT(3);
  SysWrite(1, "after", 5)
END predhalt.
