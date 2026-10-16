MODULE strictaddress;
  (* -strict reports the address of an external procedure itself, beside
     the declaration and SYSTEM.ADDRESS *)
  IMPORT SYSTEM;
  VAR a: SYSTEM.ADDRESS;
  PROCEDURE ["C", "abs"] CAbs(x: INTEGER): INTEGER;
BEGIN
  a := SYSTEM.VAL(SYSTEM.ADDRESS, CAbs)
END strictaddress.
