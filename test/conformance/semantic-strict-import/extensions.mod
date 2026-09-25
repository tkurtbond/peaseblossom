MODULE extensions;
  (* Uses poc's extensions freely; imported by a -strict module, it is not
     checked for them. *)
  IMPORT SYSTEM;
  VAR count*: HUGEINT; flags*: SYSTEM.SET64;
  PROCEDURE ["C", "abs"] Abs*(x: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE Bump*;
  BEGIN
    ASSERT(count >= 0); INC(count); INCL(flags, 40)
  END Bump;
END extensions.
