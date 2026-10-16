MODULE TreeUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10): VMSLIB's
     BalancedTrees, a tree of the program's records made by NEW, with a
     collection between the inserts and the walks to show that the tree
     keeps its nodes; then LIB$INSERT_TREE and LIB$TRAVERSE_TREE through
     declarations of the program's own, to show whether the allocate
     routine is called for a duplicate refused and whether an action's
     failure stops a walk. *)
  IMPORT SYSTEM, Out, BalancedTrees, GarbageCollectedHeap, LIBDEF, SSDEF;

  TYPE
    Word = POINTER TO WordDesc;
    WordDesc = RECORD (BalancedTrees.NodeDesc)
      text: ARRAY 16 OF CHAR;
      count: INTEGER
    END;

    RawCompare = PROCEDURE (symbol, node: SYSTEM.ADDRESS): SYSTEM.INT32;
    RawAllocate = PROCEDURE (symbol: SYSTEM.ADDRESS; VAR newNode: SYSTEM.ADDRESS): SYSTEM.INT32;
    RawAction = PROCEDURE (node, data: SYSTEM.ADDRESS): SYSTEM.INT32;

  VAR
    words, repeats: BalancedTrees.Tree;
    found: BalancedTrees.Node;
    key: Word;
    status: SYSTEM.INT32;
    visits, allocations: INTEGER;
    kept: ARRAY 6 OF Word; (* the raw tree's nodes, kept for the collector *)
    rawHead, newNode: SYSTEM.ADDRESS;

  PROCEDURE ["VMS", "LIB$INSERT_TREE"] RawInsert(VAR treehead: SYSTEM.ADDRESS; symbol: SYSTEM.ADDRESS;
    flags-: SYSTEM.CARD32; compare: RawCompare; allocate: RawAllocate;
    VAR newNode: SYSTEM.ADDRESS; userData: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$TRAVERSE_TREE"] RawTraverse(VAR treehead: SYSTEM.ADDRESS; action: RawAction;
    userData: SYSTEM.ADDRESS): SYSTEM.INT32;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = LIBDEF.LIB$_NORMAL THEN Out.String("LIB$_NORMAL")
    ELSIF status = LIBDEF.LIB$_KEYALRINS THEN Out.String("LIB$_KEYALRINS")
    ELSIF status = LIBDEF.LIB$_KEYNOTFOU THEN Out.String("LIB$_KEYNOTFOU")
    ELSIF status = SSDEF.SS$_ABORT THEN Out.String("SS$_ABORT")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  PROCEDURE NewWord(text: ARRAY OF CHAR): Word;
    VAR w: Word;
  BEGIN
    NEW(w); COPY(text, w.text); w.count := 1;
    RETURN w
  END NewWord;

  PROCEDURE CompareWords(a, b: BalancedTrees.Node): LONGINT;
    VAR result: LONGINT;
  BEGIN
    IF a(Word).text < b(Word).text THEN result := -1
    ELSIF a(Word).text > b(Word).text THEN result := 1
    ELSE result := 0
    END;
    RETURN result
  END CompareWords;

  (* text put in tree, refused or counted if it is there *)
  PROCEDURE Put(VAR tree: BalancedTrees.Tree; text: ARRAY OF CHAR; duplicates: BOOLEAN);
    VAR w: Word;
  BEGIN
    w := NewWord(text);
    status := BalancedTrees.Insert(tree, w, CompareWords, duplicates, found);
    Out.String("  "); Out.String(text);
    IF found = w THEN Out.String(", linked in")
    ELSIF found # NIL THEN
      Out.String(", there already: "); Out.String(found(Word).text);
      INC(found(Word).count)
    END;
    Show("", status)
  END Put;

  PROCEDURE PrintWord(node: BalancedTrees.Node): BOOLEAN;
  BEGIN
    Out.Char(" "); Out.String(node(Word).text); Out.Char("*"); Out.Int(node(Word).count, 0);
    RETURN TRUE
  END PrintWord;

  PROCEDURE PrintThree(node: BalancedTrees.Node): BOOLEAN;
  BEGIN
    INC(visits); Out.Char(" "); Out.String(node(Word).text);
    RETURN visits < 3
  END PrintThree;

  PROCEDURE Look(text: ARRAY OF CHAR);
  BEGIN
    key := NewWord(text);
    found := BalancedTrees.Lookup(words, key, CompareWords);
    Out.String("  Lookup("); Out.String(text); Out.String("): ");
    IF found = NIL THEN Out.String("NIL") ELSE Out.String(found(Word).text); Out.String(", count "); Out.Int(found(Word).count, 0) END;
    Out.Ln
  END Look;

  (* the raw tree's callbacks *)
  PROCEDURE CompareRaw(symbol, node: SYSTEM.ADDRESS): SYSTEM.INT32;
  BEGIN
    RETURN SHORT(CompareWords(SYSTEM.VAL(Word, symbol), SYSTEM.VAL(Word, node)))
  END CompareRaw;

  PROCEDURE AllocateRaw(symbol: SYSTEM.ADDRESS; VAR newNode: SYSTEM.ADDRESS): SYSTEM.INT32;
  BEGIN
    INC(allocations); newNode := symbol;
    RETURN 1
  END AllocateRaw;

  (* the third call fails *)
  PROCEDURE VisitRaw(node, data: SYSTEM.ADDRESS): SYSTEM.INT32;
    VAR w: Word;
  BEGIN
    w := SYSTEM.VAL(Word, node);
    INC(visits); Out.Char(" "); Out.String(w.text);
    IF visits = 3 THEN RETURN SSDEF.SS$_ABORT ELSE RETURN 1 END
  END VisitRaw;

  PROCEDURE RawPut(i: INTEGER; text: ARRAY OF CHAR);
  BEGIN
    kept[i] := NewWord(text); allocations := 0;
    status := RawInsert(rawHead, SYSTEM.VAL(SYSTEM.ADDRESS, kept[i]), 0, CompareRaw, AllocateRaw, newNode, 0);
    Out.String("  "); Out.String(text); Out.String(", allocate called "); Out.Int(allocations, 0);
    Out.String(", new node is the symbol: ");
    IF newNode = SYSTEM.VAL(SYSTEM.ADDRESS, kept[i]) THEN Out.String("yes") ELSE Out.String("no") END;
    Show("", status)
  END RawPut;

BEGIN
  Out.String("BalancedTrees, duplicates refused, empty: ");
  IF BalancedTrees.Empty(words) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Put(words, "pear", FALSE); Put(words, "apple", FALSE); Put(words, "fig", FALSE);
  Put(words, "apple", FALSE); Put(words, "kiwi", FALSE); Put(words, "banana", FALSE);
  Put(words, "fig", FALSE); Put(words, "cherry", FALSE); Put(words, "apple", FALSE);
  GarbageCollectedHeap.Collect;
  Out.String("after a collection, empty: ");
  IF BalancedTrees.Empty(words) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Out.String("  walk:"); status := BalancedTrees.Traverse(words, PrintWord); Out.Ln;
  Show("Traverse", status);
  visits := 0;
  Out.String("  walk of three:"); status := BalancedTrees.Traverse(words, PrintThree); Out.Ln;
  Show("Traverse", status);
  Look("kiwi"); Look("apple"); Look("plum");

  Out.String("BalancedTrees, duplicates allowed"); Out.Ln;
  Put(repeats, "b", TRUE); Put(repeats, "a", TRUE); Put(repeats, "b", TRUE);
  Put(repeats, "c", TRUE); Put(repeats, "a", TRUE);
  GarbageCollectedHeap.Collect;
  Out.String("  walk:"); status := BalancedTrees.Traverse(repeats, PrintWord); Out.Ln;

  Out.String("LIB$INSERT_TREE itself, duplicates refused"); Out.Ln;
  rawHead := 0;
  RawPut(0, "m"); RawPut(1, "d"); RawPut(2, "m"); RawPut(3, "t"); RawPut(4, "a"); RawPut(5, "z");
  Out.String("LIB$TRAVERSE_TREE itself, the third action failing:");
  visits := 0;
  status := RawTraverse(rawHead, VisitRaw, 0); Out.Ln;
  Out.String("  actions called "); Out.Int(visits, 0); Out.Ln;
  Show("  LIB$TRAVERSE_TREE", status)
END TreeUse.
