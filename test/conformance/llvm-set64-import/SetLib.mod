MODULE SetLib;
  IMPORT SYSTEM;
  CONST wide* = {0, 40}; narrow* = {3};
  TYPE R* = RECORD f*: SYSTEM.SET64; g: SYSTEM.SET64; h*: SET END;
  VAR v*: SYSTEM.SET64; w*: SET;
  PROCEDURE Make*(x: SET): SYSTEM.SET64;
  BEGIN RETURN x + {50} END Make;
BEGIN v := wide
END SetLib.
