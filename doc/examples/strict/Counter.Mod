MODULE Counter;
  (* A variable initializer, := 0, is one of poc's extensions *)
  IMPORT Out;
  VAR count: INTEGER := 0;
BEGIN
  INC(count); Out.Int(count, 0); Out.Ln
END Counter.
