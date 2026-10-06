MODULE Greeter;
  (* in a library of its own, which needs Greet's *)
  IMPORT Greet;

  PROCEDURE Twice*(n: INTEGER): INTEGER;
  BEGIN RETURN 2 * Greet.Count(n)
  END Twice;

END Greeter.
