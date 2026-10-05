MODULE strict;
  (* -strict reports each read-only parameter declared here, and nothing
     else: calling an imported procedure that has one is allowed *)
  IMPORT Lib;
  VAR n: INTEGER;
  PROCEDURE Twice(i-, j: INTEGER; s-: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN 2 * i + j + Lib.Length(s)
  END Twice;
BEGIN n := Twice(1, 2, "abc") + Lib.Length("xyz")
END strict.
