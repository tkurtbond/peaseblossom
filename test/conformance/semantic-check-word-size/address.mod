MODULE address;
  (* A LONGINT is assignable to an address no narrower than it: under -OC,
     on a 64-bit target only (semantic-address-width) *)
  IMPORT SYSTEM;
  VAR a: SYSTEM.ADDRESS; l: LONGINT;
  PROCEDURE P(x: SYSTEM.ADDRESS);
  END P;
BEGIN
  l := 5; a := l; P(l)
END address.
