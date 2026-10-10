MODULE CommandLine;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 6): what rtl/vax's Modules finds on the command line,
     kept for the debugger run, where the program is not run as a foreign
     command and so has argument 0 alone *)
  IMPORT Modules;
  VAR count: INTEGER; first, second: ARRAY 64 OF CHAR;
BEGIN
  count := Modules.ArgCount;
  Modules.GetArg(0, first);
  Modules.GetArg(1, second)
END CommandLine.
