MODULE greeter;
  (* Companion to module-import-path: same library, but this fixture's
     test.sh deliberately omits "-import-path lib", so greeter.sym (built
     into this "lib" subdirectory) must NOT be found via the current
     working directory alone. *)

  CONST Greeting* = "hello";

  PROCEDURE Greet*(): INTEGER;
  BEGIN
    RETURN 1
  END Greet;

END greeter.
