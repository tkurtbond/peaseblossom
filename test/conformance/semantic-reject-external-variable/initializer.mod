MODULE Initializer;
  (* semantic-reject-external-variable: an external variable's storage is
     defined elsewhere, so it cannot have an initializer. *)
  IMPORT SYSTEM;
  VAR ["C"] counter: SYSTEM.INT32 := 1;
END Initializer.
