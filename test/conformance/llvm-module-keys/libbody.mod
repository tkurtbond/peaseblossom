MODULE lib;
  (* libv1 with a body changed: the interface, so the key, is the same *)
  PROCEDURE Answer*(): INTEGER;
  BEGIN
    RETURN 43
  END Answer;

  PROCEDURE Twice*(n: INTEGER): INTEGER;
  BEGIN
    RETURN n + n
  END Twice;
END lib.
