MODULE Small;
(* a procedure small enough to inline across modules *)

  TYPE
    Node* = POINTER TO NodeDesc;
    NodeDesc* = RECORD value*: LONGINT; next*: Node END;

  PROCEDURE Twice*(x: LONGINT): LONGINT;
  BEGIN
    RETURN x + x
  END Twice;

  PROCEDURE Push*(VAR list: Node; value: LONGINT);
    VAR n: Node;
  BEGIN
    NEW(n); n.value := value; n.next := list; list := n
  END Push;

END Small.
