MODULE Use;
  (* vax-objconvert-counted: a program built with the object made on VMS
     from hand-Twice.mar, fetched in the counted form OBJCONVERT -COUNTED
     writes. It only takes its routines' addresses; poc -build taking the
     object is what is checked. *)
  IMPORT SYSTEM;

  VAR twice, other: SYSTEM.ADDRESS;

  PROCEDURE ["VMS", "TWICE"] Twice;
  PROCEDURE ["VMS", "OTHER"] Other;

BEGIN
  twice := SYSTEM.VAL(SYSTEM.ADDRESS, Twice);
  other := SYSTEM.VAL(SYSTEM.ADDRESS, Other)
END Use.
