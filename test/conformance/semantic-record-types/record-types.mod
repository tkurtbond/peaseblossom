MODULE recordTypes;
  (* Record type resolution (Oberon2.pdf §6.3, PLAN.md Phase 4):
     - a base record with a read-only ('-') field export mark, legal on
       a record field (Appendix A/the Trees example's "name-"), unlike
       CheckExportMark's CONST/TYPE-name callers, which reject it;
     - an extension naming that base via RECORD (Base) ..., resolved
       through Types.Extends' baseType chain. *)

  TYPE
    Node = RECORD
      name-: ARRAY 32 OF CHAR;
      value: INTEGER
    END;
    CenterNode = RECORD (Node)
      mid: INTEGER
    END;
BEGIN
END recordTypes.
