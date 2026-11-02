MODULE ownval;
  (* a program's own VAL takes what it says, as any Universe name *)
  PROCEDURE VAL(x: REAL): REAL; BEGIN RETURN x END VAL;
  VAR y: REAL;
BEGIN y := VAL(1.5)
END ownval.
