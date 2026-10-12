MODULE VaxLibBase;
  VAR count*: LONGINT;
  PROCEDURE Bump*(n: LONGINT);
  BEGIN count := count + n
  END Bump;
END VaxLibBase.
