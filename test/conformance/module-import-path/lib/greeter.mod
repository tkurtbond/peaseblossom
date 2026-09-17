MODULE greeter;
  (* PLAN.md's "Open design questions" - IMPORT search path: this module
     lives in a "lib" subdirectory, deliberately not this test's own
     directory, so client.mod (one level up) can only see greeter.sym via
     "-import-path lib" - see this fixture's own test.sh. *)

  CONST Greeting* = "hello";

  PROCEDURE Greet*(): INTEGER;
  BEGIN
    RETURN 1
  END Greet;

END greeter.
