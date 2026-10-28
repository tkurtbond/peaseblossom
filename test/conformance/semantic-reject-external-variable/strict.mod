MODULE Strict;
  (* semantic-reject-external-variable: -strict rejects an external
     variable. *)
  VAR ["C"] counter: LONGINT;
BEGIN
  counter := 1
END Strict.
