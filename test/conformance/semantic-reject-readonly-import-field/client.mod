MODULE client;
  IMPORT trees;
  VAR t: trees.Tree;
  PROCEDURE X;
  BEGIN
    t := trees.NewTree();
    t.name := NIL
  END X;
END client.
