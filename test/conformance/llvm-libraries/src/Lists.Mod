MODULE Lists;
  IMPORT Out;
  TYPE
    List* = POINTER TO Node;
    Node* = RECORD value*: INTEGER; next*: List END;
    Counter* = POINTER TO RECORD n*: INTEGER END;
  VAR made*: INTEGER;
  PROCEDURE Push*(VAR l: List; v: INTEGER);
    VAR n: List;
  BEGIN
    NEW(n); n.value := v; n.next := l; l := n; INC(made)
  END Push;
  PROCEDURE Print*(l: List);
  BEGIN
    WHILE l # NIL DO Out.Int(l.value, 0); Out.Char(" "); l := l.next END; Out.Ln
  END Print;
  PROCEDURE (n: List) Sum*(): INTEGER;
    VAR s: INTEGER;
  BEGIN
    s := 0; WHILE n # NIL DO INC(s, n.value); n := n.next END; RETURN s
  END Sum;
BEGIN
  Out.String("Lists ready"); Out.Ln
END Lists.
