MODULE WordSets;  (* which words are in one file, the other, or both *)

  IMPORT Coroutines, Files, Args, Out;

  CONST maxWord = 64;

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      word: ARRAY maxWord OF CHAR;
      left, right: Node
    END;
    Walker = RECORD
      cor: Coroutines.Coroutine;
      tree: Node;
      current: Node   (* the word handed over; NIL after the last *)
    END;

  VAR
    main: Coroutines.Coroutine;
    a, b: Walker;
    name: ARRAY 256 OF CHAR;

  PROCEDURE Insert(VAR t: Node; VAR word: ARRAY OF CHAR);
  BEGIN
    IF t = NIL THEN NEW(t); COPY(word, t.word)
    ELSIF word < t.word THEN Insert(t.left, word)
    ELSIF word > t.word THEN Insert(t.right, word)
    END
  END Insert;

  PROCEDURE IsWordChar(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (CAP(ch) >= "A") & (CAP(ch) <= "Z") OR (ch >= "0") & (ch <= "9")
  END IsWordChar;

  PROCEDURE ReadWords(name: ARRAY OF CHAR; VAR tree: Node);
    VAR f: Files.File; r: Files.Rider; ch: CHAR;
      word: ARRAY maxWord OF CHAR; i: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN
      Out.String("cannot open "); Out.String(name); Out.Ln; HALT(1)
    END;
    Files.Set(r, f, 0); Files.Read(r, ch);
    WHILE ~r.eof DO
      IF IsWordChar(ch) THEN
        i := 0;
        REPEAT
          IF i < maxWord - 1 THEN word[i] := ch; INC(i) END;
          Files.Read(r, ch)
        UNTIL r.eof OR ~IsWordChar(ch);
        word[i] := 0X; Insert(tree, word)
      ELSE Files.Read(r, ch)
      END
    END
  END ReadWords;

  PROCEDURE Height(t: Node): LONGINT;
    VAR l, r: LONGINT;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    l := Height(t.left); r := Height(t.right);
    IF l > r THEN RETURN l + 1 ELSE RETURN r + 1 END
  END Height;

  (* The walk: ordinary in-order recursion, handing each node to main. *)
  PROCEDURE Walk(t: Node; VAR w: Walker);
  BEGIN
    IF t # NIL THEN
      Walk(t.left, w);
      w.current := t; Coroutines.Transfer(w.cor, main);
      Walk(t.right, w)
    END
  END Walk;

  (* A body must not return: after the last word, hand over NIL forever. *)
  PROCEDURE Finish(VAR w: Walker);
  BEGIN
    w.current := NIL;
    LOOP Coroutines.Transfer(w.cor, main) END
  END Finish;

  PROCEDURE WalkA; BEGIN Walk(a.tree, a); Finish(a) END WalkA;
  PROCEDURE WalkB; BEGIN Walk(b.tree, b); Finish(b) END WalkB;

  PROCEDURE Next(VAR w: Walker);
  BEGIN Coroutines.Transfer(main, w.cor)
  END Next;

  PROCEDURE Show(mark: CHAR; n: Node);
  BEGIN Out.Char(mark); Out.Char(" "); Out.String(n.word); Out.Ln
  END Show;

BEGIN
  IF Args.argc # 3 THEN
    Out.String("usage: wordsets file1 file2"); Out.Ln; HALT(2)
  END;
  Args.Get(1, name); ReadWords(name, a.tree);
  Args.Get(2, name); ReadWords(name, b.tree);
  (* A walk is as deep as its tree is high; sorted input makes a list. *)
  Coroutines.Init(WalkA, 16384 + 256 * Height(a.tree), a.cor);
  Coroutines.Init(WalkB, 16384 + 256 * Height(b.tree), b.cor);
  Next(a); Next(b);
  WHILE (a.current # NIL) OR (b.current # NIL) DO
    IF (b.current = NIL) OR (a.current # NIL) & (a.current.word < b.current.word) THEN
      Show("<", a.current); Next(a)
    ELSIF (a.current = NIL) OR (b.current.word < a.current.word) THEN
      Show(">", b.current); Next(b)
    ELSE
      Show("=", a.current); Next(a); Next(b)
    END
  END
END WordSets.
