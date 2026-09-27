MODULE lib;
  (* the first version of lib: Answer and Twice *)
  PROCEDURE Answer*(): INTEGER;
  BEGIN
    RETURN 42
  END Answer;

  PROCEDURE Twice*(n: INTEGER): INTEGER;
  BEGIN
    RETURN 2 * n
  END Twice;
END lib.
