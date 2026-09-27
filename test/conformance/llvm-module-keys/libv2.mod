MODULE lib;
  (* libv1 with Twice's parameter widened: a new interface, so a new key *)
  PROCEDURE Answer*(): INTEGER;
  BEGIN
    RETURN 42
  END Answer;

  PROCEDURE Twice*(n: LONGINT): LONGINT;
  BEGIN
    RETURN 2 * n
  END Twice;
END lib.
