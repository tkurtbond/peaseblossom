MODULE SetUse;
  IMPORT SetLib, SYSTEM, Out;
  VAR r: SetLib.R; q: SYSTEM.SET64;
BEGIN
  r.f := SetLib.wide; q := SetLib.Make(SetLib.narrow) + SetLib.v;
  IF 40 IN q THEN Out.String("40 ") END; IF 50 IN q THEN Out.String("50 ") END; IF 3 IN q THEN Out.String("3") END; Out.Ln;
  IF 40 IN r.f THEN Out.String("yes") END; Out.Ln
END SetUse.
