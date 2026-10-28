MODULE Use;
  (* twice is in an object named on the command line *)
  IMPORT SYSTEM, Out;

  PROCEDURE ["C", "twice"] Twice(x: SYSTEM.INT32): SYSTEM.INT32;

BEGIN
  Out.Int(Twice(21), 0); Out.Ln
END Use.
