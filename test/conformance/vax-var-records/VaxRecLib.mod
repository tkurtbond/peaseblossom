MODULE VaxRecLib;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 5): imported by VaxVarRecords. Pair, a record holding
     pointers, is passed to Count as a VAR parameter, with its tag. *)
  TYPE
    Node* = POINTER TO NodeDesc;
    NodeDesc* = RECORD v*: INTEGER; next*: Node END;
    Pair* = RECORD a*, b*: Node; n*: INTEGER END;

  (* The nodes of p's two lists, and n *)
  PROCEDURE Count*(VAR p: Pair): INTEGER;
    VAR k: INTEGER; q: Node;
  BEGIN
    k := p.n;
    q := p.a; WHILE q # NIL DO INC(k); q := q.next END;
    q := p.b; WHILE q # NIL DO INC(k); q := q.next END;
    RETURN k
  END Count;
END VaxRecLib.
