MODULE Twice;
  IMPORT Greet;

  PROCEDURE Do*(n: INTEGER);
  BEGIN
    Greet.Hi(n); Greet.Hi(n + 1)
  END Do;

END Twice.
