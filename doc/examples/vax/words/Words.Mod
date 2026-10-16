MODULE Words;
  IMPORT SYSTEM, Out, BalancedTrees, LIBDEF;

  TYPE
    Word = POINTER TO WordDesc;
    WordDesc = RECORD (BalancedTrees.NodeDesc)
      text: ARRAY 16 OF CHAR;
      count: INTEGER
    END;

  VAR
    tree: BalancedTrees.Tree;
    status: SYSTEM.INT32;

  PROCEDURE Compare(a, b: BalancedTrees.Node): LONGINT;
  BEGIN
    IF a(Word).text < b(Word).text THEN RETURN -1
    ELSIF a(Word).text = b(Word).text THEN RETURN 0
    ELSE RETURN 1
    END
  END Compare;

  PROCEDURE Add(text: ARRAY OF CHAR);
    VAR w: Word; found: BalancedTrees.Node; status: SYSTEM.INT32;
  BEGIN
    NEW(w); COPY(text, w.text); w.count := 1;
    status := BalancedTrees.Insert(tree, w, Compare, FALSE, found);
    IF status = LIBDEF.LIB$_KEYALRINS THEN INC(found(Word).count) END
  END Add;

  PROCEDURE Print(n: BalancedTrees.Node): BOOLEAN;
  BEGIN
    Out.String(n(Word).text); Out.Char(" "); Out.Int(n(Word).count, 0); Out.Ln;
    RETURN TRUE
  END Print;

BEGIN
  Add("the"); Add("quick"); Add("brown"); Add("fox"); Add("jumps");
  Add("over"); Add("the"); Add("lazy"); Add("dog"); Add("the");
  status := BalancedTrees.Traverse(tree, Print)
END Words.
