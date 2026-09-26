MODULE names;
  (* Phase 11 A25: "_" and "$" are not identifier characters (the Oberon-2
     report: letters and digits only). Each name that has one costs one
     error, where the character is, and nothing after it. *)
  VAR
    a_b, SYS$QIO, _leading, trailing_: INTEGER;
    ok: INTEGER;
BEGIN
  a_b := 1; ok := a_b
END names.
