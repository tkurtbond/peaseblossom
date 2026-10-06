MODULE IfLines;
  (* The IF is on line 7 and its ELSIFs on 9 and 12: each condition's
     branch must carry its own line, not the last ELSIF's (the IF did) or
     the previous branch body's (the ELSIFs did). *)
  VAR i, j: INTEGER;
BEGIN
  i := 3; IF i = 1 THEN
    j := 10
  ELSIF i = 2 THEN
    j := 20
  ELSE
    IF i = 3 THEN j := 30 ELSIF i = 4 THEN j := 40 END
  END
END IfLines.
