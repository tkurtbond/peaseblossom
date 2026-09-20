MODULE filesfail;
  (* PLAN.md Phase 10 step 3: a file that cannot be created is fatal, with
     a message naming it and Halt(99), as in voc. *)
  IMPORT Files, Console;
  VAR f: Files.File; r: Files.Rider;
BEGIN
  f := Files.New("no-such-directory/data");
  Files.Set(r, f, 0);
  Console.String("before"); Console.Ln;
  Files.Write(r, "x");
  Console.String("not reached"); Console.Ln
END filesfail.
