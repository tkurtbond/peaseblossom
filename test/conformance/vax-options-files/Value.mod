MODULE Value;
  (* vax-options-files (doc/developer/vax-macro32-backend.md, section
     13.3): SEVEN_VALUE, which only an options file defines, printed as
     the address of an external procedure, SYSTEM.VAL(SYSTEM.ADDRESS, E). *)
  IMPORT SYSTEM, Out;

  PROCEDURE ["VMS", "SEVEN_VALUE"] SevenValue;

BEGIN
  Out.String("SEVEN_VALUE is "); Out.Int(SYSTEM.VAL(SYSTEM.ADDRESS, SevenValue), 0); Out.Ln
END Value.
