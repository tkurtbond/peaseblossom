MODULE typeDecls;
  (* TYPE declarations exercising basic-type aliasing and the forward
     POINTER TO reference Oberon2.pdf §4 rule 3 allows (a pointer's base
     type may be declared later in the same block). Array, record, and
     procedure types are PLAN.md Phase 4/6 work, so - and the still-open
     "must be a record or array type" pointer-base rule (§6.4) along with
     them - are deliberately absent here; see SemanticActions.ResolveType. *)

  TYPE
    MyInt = INTEGER;
    IntPtr = POINTER TO Int; (* Int is declared below: a forward reference *)
    Int = INTEGER;
    AliasOfAlias = MyInt;
BEGIN
END typeDecls.
