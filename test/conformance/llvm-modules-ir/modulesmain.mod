MODULE modulesmain;
  (* PLAN.md Phase 10 step 4: a program that contains Modules gets a main
     taking argc and argv, which it hands to Modules.Init before any module
     body; test.sh shows just that part of the IR, for the 64-bit host and
     for i686. *)
  IMPORT Modules;
  VAR n: INTEGER;
BEGIN
  n := Modules.ArgCount
END modulesmain.
