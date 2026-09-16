MODULE exitOutsideLoop;
  (* Oberon2.pdf §9.9/9.10: EXIT terminates the innermost enclosing LOOP
     statement specifically - WHILE is not LOOP, so EXIT here has no
     enclosing LOOP to terminate. *)

  VAR b: BOOLEAN;
BEGIN
  WHILE b DO
    EXIT
  END
END exitOutsideLoop.
