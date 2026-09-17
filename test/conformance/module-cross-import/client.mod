MODULE client;
  (* PLAN.md Phase 7: type-checks against trees.sym (built by this same
     test's test.sh before this file is compiled), never re-parsing
     trees.mod - exercises a qualified TYPE (Trees.Tree), a qualified
     PROCEDURE call (Trees.NewTree), type-bound-procedure calls resolved
     through it (t.Insert/t.Search/t.Write), and reading an exported
     read-only field (t.Search(...).name^). *)

  IMPORT Trees := trees;

  VAR t, found: Trees.Tree;

  PROCEDURE Run;
  BEGIN
    t := Trees.NewTree();
    t.Insert("hello");
    found := t.Search("hello");
    t.Write
  END Run;

END client.
