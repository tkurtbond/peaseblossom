MODULE Bad;
  (* The error below must be reported as lib/Bad.Mod:5:3, the file poc read. *)
  VAR x: INTEGER;
BEGIN
  x := TRUE
END Bad.
