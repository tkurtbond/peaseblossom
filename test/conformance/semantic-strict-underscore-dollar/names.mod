MODULE names;
  (* Phase 11 A25, reopened 2026-09-26: "_" and "$" are identifier characters
     anywhere, first included - poc's extension for VMS names. Without
     -strict this checks; under -strict each name that has one costs one
     error, at the first of them. *)
  VAR
    a_b, SYS$QIO, _leading, trailing_, $first, SS$_NORMAL: INTEGER;
    ok: INTEGER;
BEGIN
  a_b := 1; ok := a_b
END names.
