MODULE usetables;
(* Phase 14: the constants of Tables, imported *)
IMPORT Out, Tables;
VAR i: INTEGER;
BEGIN
  FOR i := 0 TO 7 DO Out.Int(Tables.sparse[i], 2) END; Out.String(Tables.grid[2]); Out.Ln
END usetables.
