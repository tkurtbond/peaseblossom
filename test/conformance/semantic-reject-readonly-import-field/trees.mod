MODULE trees;
  (* PLAN.md Phase 7: the report's own Ch.11 Trees example again - name-
     is exported read-only, so the client in this same directory must be
     rejected for writing t.name (reached through a local variable of
     the imported pointer type, not a directly-qualified reference -
     the realistic shape this check has to catch). *)

  TYPE
    Tree* = POINTER TO Node;
    Node* = RECORD
      name-: POINTER TO ARRAY OF CHAR;
      left, right: Tree
    END;

  PROCEDURE NewTree*(): Tree;
  VAR t: Tree;
  BEGIN
    NEW(t); NEW(t.name, 1); t.name[0] := 0X; t.left := NIL; t.right := NIL;
    RETURN t
  END NewTree;

END trees.
