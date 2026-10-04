MODULE client;
  IMPORT lib;
  CONST d = lib.Dyn{k := 1}; e = lib.Dyn{n := 1}; row* = lib.m[1];
  VAR i: INTEGER; x: lib.Secret;
BEGIN
  i := lib.s.hidden;
  x := lib.s;
  lib.s.a := 1
END client.
