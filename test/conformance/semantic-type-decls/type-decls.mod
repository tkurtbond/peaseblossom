MODULE typeDecls;
  (* TYPE declarations exercising basic-type aliasing and the forward
     POINTER TO reference Oberon2.pdf §4 rule 3 allows (a pointer's base
     type may be declared later in the same block). Array/record/
     procedure-type-specific fixtures (semantic-array-types,
     semantic-record-types, semantic-procedure-types) and the composite-
     type reject fixtures live separately (PLAN.md Phase 4); this one
     keeps its original Phase 3 focus of basic-type aliasing plus the
     rule-3 forward reference - now satisfied with RECORD, the only
     legal pointer base per §6.4 (see SemanticActions.ResolveType). *)

  TYPE
    MyInt = INTEGER;
    NodePtr = POINTER TO Node; (* Node is declared below: a forward reference *)
    Node = RECORD END;
    AliasOfAlias = MyInt;
BEGIN
END typeDecls.
