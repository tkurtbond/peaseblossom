MODULE procedureTypedCall;
  (* Calling through a procedure-typed value (Oberon2.pdf §6.5/§9.2,
     PLAN.md Phase 5): recognizes Types.ProcedureType as callable,
     including a procedure-typed record field - the semantic-procedure-
     types fixture's own Table/Comparator family, extended here with an
     actual call statement and call expression. There is no way yet to
     give cmp/apply a real value (PROCEDURE declarations are PLAN.md
     Phase 6), so this only exercises static call-shape checking, not a
     runnable program - matching parameter-list matching itself being
     explicitly deferred to Phase 6 (see SemanticActions.Mod's Phase 5
     header comment). *)

  TYPE
    Comparator = PROCEDURE (x, y: INTEGER): BOOLEAN;
    Table = RECORD
      compare: Comparator;
      apply: PROCEDURE (n: INTEGER)
    END;

  VAR
    t: Table;
    f: Comparator;
    b: BOOLEAN;
BEGIN
  b := t.compare(1, 2);
  b := f(3, 4);
  t.apply(5)
END procedureTypedCall.
