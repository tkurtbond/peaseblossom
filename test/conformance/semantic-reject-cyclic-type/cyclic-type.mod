MODULE cyclicType;
  (* Node's base is itself, which is never a record or array type (§6.4) -
     PLAN.md Phase 4's more precise diagnosis of what was, pre-Phase-4,
     reported as a generic "illegal cyclic type declaration" (that
     message remains reachable for other, still-unaddressed self-
     reference shapes - see SemanticActions.Mod's header comment on
     ResolveType). *)
  TYPE
    Node = POINTER TO Node;
BEGIN
END cyclicType.
