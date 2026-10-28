MODULE Value;
  (* vax-options-files (doc/developer/vax-macro32-backend.md, section
     13.3): SEVEN_VALUE, which only an options file defines, printed as
     the address of an external variable (doc/developer/language-extensions.md,
     "External variables"). *)
  IMPORT SYSTEM, Out;

  VAR ["VMS", "SEVEN_VALUE"] sevenValue: SYSTEM.BYTE;

BEGIN
  Out.String("SEVEN_VALUE is "); Out.Int(SYSTEM.ADR(sevenValue), 0); Out.Ln
END Value.
