MODULE Lib;
  IMPORT SYSTEM;
  TYPE
    Big* = RECORD a*: ARRAY 8 OF SYSTEM.INT32 END;
    Counter* = PROCEDURE (s-: ARRAY OF CHAR; b-: Big): LONGINT;
  PROCEDURE Count*(s-: ARRAY OF CHAR; b-: Big): LONGINT;
    VAR k: LONGINT;
  BEGIN k := 0; WHILE s[k] # 0X DO INC(k) END; RETURN k + b.a[7]
  END Count;
END Lib.
