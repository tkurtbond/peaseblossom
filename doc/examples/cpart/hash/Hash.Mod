MODULE Hash;
  (* FNV-1a, computed by the module's C part, Hash.c beside this file *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "hash_fnv1a"] Fnv1a(s, n: SYSTEM.ADDRESS): SYSTEM.INT32;

  PROCEDURE Of*(s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0; WHILE s[n] # 0X DO INC(n) END;
    RETURN Fnv1a(SYSTEM.ADR(s), n)
  END Of;
END Hash.
