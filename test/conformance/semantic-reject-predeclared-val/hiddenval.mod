MODULE hiddenval;
  (* its own VAL is not in the .sym file, so that means the predeclared one *)
  PROCEDURE VAL(x: INTEGER): INTEGER; BEGIN RETURN x END VAL;
  CONST top* = MAX(CARDINAL);
END hiddenval.
