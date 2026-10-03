MODULE Absolute;
  (* abs from the C library: C's int is SYSTEM.INT32 under both size models *)
  IMPORT SYSTEM, Out;

  PROCEDURE ["C", "abs"] CAbs(x: SYSTEM.INT32): SYSTEM.INT32;

BEGIN
  Out.Int(CAbs(-42), 0); Out.Ln
END Absolute.
