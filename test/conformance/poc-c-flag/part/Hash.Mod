MODULE Hash;
(* FNV-1a in the module's C part, Hash.c, whose header is in ../include *)
IMPORT SYSTEM;
PROCEDURE ["C", "poc_fixture_fnv1a"] Fnv1a(s: SYSTEM.ADDRESS; n: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE Of*(s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE s[n] # 0X DO INC(n) END;
  RETURN Fnv1a(SYSTEM.ADR(s), n)
END Of;
END Hash.
