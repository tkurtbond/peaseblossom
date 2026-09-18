MODULE lib;
  (* PLAN.md Phase 8 step 12's dedicated compile+link+run+diff-stdout
     fixture for the whole-program driver: the library half of a real,
     two-module Oberon-to-Oberon IMPORT, transitively discovered and
     compiled from its own real ".mod" source (not just type-checked
     against its .sym interface, the only thing IMPORT resolution needed
     before this step) - see client.mod in this same directory for the
     other half. Exports a VAR and two ordinary procedures, everything
     Phase 8's own codegen already supports (no POINTER/NEW - Phase 9),
     so client.mod's own qualified references to all three (Lib.total,
     Lib.Add, Lib.Accumulate) exercise every qualified-designator/call
     codegen path step 12 adds. *)
  VAR total*: INTEGER;

  PROCEDURE Add*(a, b: INTEGER): INTEGER;
  BEGIN
    RETURN a + b
  END Add;

  PROCEDURE Accumulate*(n: INTEGER);
  BEGIN
    total := total + n
  END Accumulate;

BEGIN
  total := 100
END lib.
