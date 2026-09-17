MODULE withQualifiedGuard;
  (* WITH Lib.t: T DO is syntactically legal (Oberon2.pdf §9.11's own
     Guard = Qualident ":" Qualident), but SemanticActions.Mod's
     CheckWithGuard now rejects any module-qualified guard variable
     unconditionally - see that procedure's own header comment for the
     full rationale and how it was reverse-engineered against real voc.
     The narrowing is skipped once rejected (poison-propagated as
     Types.Undefined), so the guard body's own "Lib.t.weight" access
     falls through to an ordinary, still-unnarrowed qualified designator
     lookup and is separately rejected too - Node has no "weight" field,
     only CenterNode does. *)

  IMPORT Lib := withlib;

  VAR w: INTEGER;
BEGIN
  WITH Lib.t: Lib.CenterTree DO
    w := Lib.t.weight
  END
END withQualifiedGuard.
