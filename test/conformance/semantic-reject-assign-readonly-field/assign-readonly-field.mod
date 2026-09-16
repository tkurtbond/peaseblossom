MODULE assignReadonlyField;
  (* Field-level read-only-ness propagates through '.' (Oberon2.pdf §8.1,
     PLAN.md Phase 5): assigning to a '-'-marked record field is
     rejected. *)

  TYPE T = RECORD f-: INTEGER END;
  VAR t: T;
BEGIN
  t.f := 5
END assignReadonlyField.
