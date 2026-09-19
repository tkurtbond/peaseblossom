MODULE Trees;
  (* Oberon2.pdf's Chapter 11 example, whose keys are strings held through
     open arrays: a binary tree of names, Insert and Search taking an
     ARRAY OF CHAR, each node's name a POINTER TO ARRAY OF CHAR allocated
     with NEW(p.name, LEN(name)+1) and filled by COPY, compared with
     "name = p.name^". (The 2022 revision's form, with NewTree(): Tree in
     place of an Init procedure.) Only what the example does with Texts
     and Oberon.Log is different: Write puts each name straight to
     write(2), a space after it. *)
  TYPE
    Tree* = POINTER TO Node;
    Node* = RECORD
      name-: POINTER TO ARRAY OF CHAR;
      left, right: Tree
    END;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE (t: Tree) Insert* (name: ARRAY OF CHAR);
    VAR p, father: Tree;
  BEGIN p := t;
    REPEAT father := p;
      IF name = p.name^ THEN RETURN END;
      IF name < p.name^ THEN p := p.left ELSE p := p.right END
    UNTIL p = NIL;
    NEW(p); p.left := NIL; p.right := NIL; NEW(p.name, LEN(name)+1); COPY(name, p.name^);
    IF name < father.name^ THEN father.left := p ELSE father.right := p END
  END Insert;

  PROCEDURE (t: Tree) Search* (name: ARRAY OF CHAR): Tree;
    VAR p: Tree;
  BEGIN p := t;
    WHILE (p # NIL) & (name # p.name^) DO
      IF name < p.name^ THEN p := p.left ELSE p := p.right END
    END;
    RETURN p
  END Search;

  PROCEDURE (t: Tree) Write*;
    VAR length: INTEGER;
  BEGIN
    IF t.left # NIL THEN t.left.Write END;
    length := 0;
    WHILE t.name[length] # 0X DO INC(length) END;
    SysWrite(1, t.name^, length); SysWrite(1, " ", 1);
    IF t.right # NIL THEN t.right.Write END
  END Write;

  PROCEDURE NewTree* (): Tree;
    VAR t: Tree;
  BEGIN NEW(t); NEW(t.name, 1); t.name[0] := 0X; t.left := NIL; t.right := NIL; RETURN t
  END NewTree;

END Trees.
