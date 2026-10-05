MODULE Lib;
  PROCEDURE Length*(s-: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN k := 0; WHILE s[k] # 0X DO INC(k) END; RETURN k
  END Length;
END Lib.
