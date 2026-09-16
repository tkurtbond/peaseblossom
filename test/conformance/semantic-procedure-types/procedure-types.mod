MODULE procedureTypes;
  (* Procedure type resolution (Oberon2.pdf §6.5, PLAN.md Phase 4): a
     function type with a VAR and a value parameter plus a result type,
     used both as a TYPE alias and as a record field type alongside a
     proper-procedure (no result) field type. *)

  TYPE
    Comparator = PROCEDURE (VAR x: INTEGER; y: INTEGER): BOOLEAN;
    Table = RECORD
      compare: Comparator;
      apply: PROCEDURE (n: INTEGER)
    END;
BEGIN
END procedureTypes.
