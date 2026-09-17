MODULE trees;
  (* Oberon2.pdf Ch.11's own Trees example, as the library half of a
     cross-module conformance test (PLAN.md Phase 7): the client module
     in this same directory IMPORTs this one and type-checks purely
     against trees.sym, never re-parsing this source. *)

  TYPE
    Tree* = POINTER TO Node;
    Node* = RECORD
      name-: POINTER TO ARRAY OF CHAR;
      left, right: Tree
    END;

  PROCEDURE (t: Tree) Insert*(name: ARRAY OF CHAR);
  VAR p, father: Tree;
  BEGIN
    p := t;
    REPEAT
      father := p;
      IF name = p.name^ THEN RETURN END;
      IF name < p.name^ THEN p := p.left ELSE p := p.right END
    UNTIL p = NIL
  END Insert;

  PROCEDURE (t: Tree) Search*(name: ARRAY OF CHAR): Tree;
  VAR p: Tree;
  BEGIN
    p := t;
    WHILE (p # NIL) & (name # p.name^) DO
      IF name < p.name^ THEN p := p.left ELSE p := p.right END
    END;
    RETURN p
  END Search;

  PROCEDURE (t: Tree) Write*;
  BEGIN
    IF t.left # NIL THEN t.left.Write END;
    IF t.right # NIL THEN t.right.Write END
  END Write;

  PROCEDURE NewTree*(): Tree;
  VAR t: Tree;
  BEGIN
    NEW(t); NEW(t.name, 1); t.name[0] := 0X; t.left := NIL; t.right := NIL;
    RETURN t
  END NewTree;

END trees.
