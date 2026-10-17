MODULE Fault;
  IMPORT Out;

  VAR none: INTEGER;

  PROCEDURE Average(total, count: INTEGER): INTEGER;
  BEGIN
    RETURN total DIV count
  END Average;

BEGIN
  Out.Int(Average(10, 2), 0); Out.Ln;
  Out.Int(Average(10, none), 0); Out.Ln
END Fault.
