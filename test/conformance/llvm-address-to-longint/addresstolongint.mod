MODULE AddressToLongint;
  (* Under -OC an ADDRESS is assignable to a LONGINT on every target: on a
     64-bit one they are the same width and include each other, on a 32-bit
     one the LONGINT is wider. *)
  IMPORT SYSTEM, Out;
  VAR a: SYSTEM.ADDRESS; x: LONGINT; s: ARRAY 8 OF CHAR;

  PROCEDURE Next(n: LONGINT): LONGINT;
  BEGIN RETURN n + 1
  END Next;

  PROCEDURE Offset(): LONGINT;
  BEGIN RETURN SYSTEM.ADR(s[3]) - SYSTEM.ADR(s[0])
  END Offset;

BEGIN
  a := SYSTEM.ADR(s[5]) - SYSTEM.ADR(s[0]);
  x := a; Out.Int(x, 0); Out.Ln;
  Out.Int(Next(a), 0); Out.Ln;
  Out.Int(Offset(), 0); Out.Ln;
  a := -7; x := a; Out.Int(x, 0); Out.Ln;
  x := a + 1; Out.Int(x, 0); Out.Ln
END AddressToLongint.
