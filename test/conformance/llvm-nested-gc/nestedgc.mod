MODULE nestedgc;
  IMPORT SYSTEM; (* write's int and size_t are 4 bytes on a 32-bit target under -OC too *)
  (* Phase 11 step 8, step 3 (doc/nested-procedures.md): the collector and a
     nested procedure's access to an enclosing variable. The pointers here live
     only in variables of an enclosing procedure (a local, a VAR parameter, a
     record field, an element of a local array) and are reached and changed by
     nested procedures that allocate far more than the heap starts with, so a
     collection runs while the only reference to an object is in the enclosing
     frame. "NN ok" or "NN BAD" per check. *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node; value: INTEGER END;
    Box = RECORD held: Node END;

  PROCEDURE ["C", "write"] SysWrite(fd: SYSTEM.INT32; s: ARRAY OF CHAR; n: SYSTEM.ADDRESS);

  PROCEDURE Report(number: INTEGER; ok: BOOLEAN);
    VAR line: ARRAY 12 OF CHAR;
  BEGIN
    line[0] := CHR(ORD("0") + number DIV 10); line[1] := CHR(ORD("0") + number MOD 10); line[2] := " ";
    IF ok THEN
      line[3] := "o"; line[4] := "k"; line[5] := 0AX; SysWrite(1, line, 6)
    ELSE
      line[3] := "B"; line[4] := "A"; line[5] := "D"; line[6] := 0AX; SysWrite(1, line, 7)
    END
  END Report;

  PROCEDURE Sum(head: Node): LONGINT;
    VAR t: LONGINT;
  BEGIN
    t := 0;
    WHILE head # NIL DO t := t + head.value; head := head.next END;
    RETURN t
  END Sum;

  (* the list is built by a nested procedure into a local of the enclosing one;
     Churn then allocates and drops many blocks *)
  PROCEDURE Local(): LONGINT;
    VAR list: Node;
    PROCEDURE Push(v: INTEGER);
      VAR n: Node;
    BEGIN
      NEW(n); n.value := v; n.next := list; list := n
    END Push;
    PROCEDURE Churn(rounds: LONGINT);
      VAR temp: Node; i: LONGINT;
    BEGIN
      FOR i := 1 TO rounds DO NEW(temp); temp.value := SHORT(i MOD 100) END
    END Churn;
    PROCEDURE Fill;
      VAR i: INTEGER;
    BEGIN
      FOR i := 1 TO 50 DO Push(i); IF i MOD 10 = 0 THEN Churn(50000) END END
    END Fill;
  BEGIN
    list := NIL; Fill; Churn(200000);
    RETURN Sum(list)
  END Local;

  (* the same through a VAR parameter: the caller's pointer *)
  PROCEDURE ThroughVar(VAR list: Node);
    PROCEDURE Push(v: INTEGER);
      VAR n: Node;
    BEGIN
      NEW(n); n.value := v; n.next := list; list := n
    END Push;
    PROCEDURE Churn;
      VAR temp: Node; i: LONGINT;
    BEGIN
      FOR i := 1 TO 100000 DO NEW(temp) END
    END Churn;
  BEGIN
    Push(1); Churn; Push(2); Churn; Push(3); Churn
  END ThroughVar;

  (* a pointer in a record field and in an array element of the enclosing
     procedure, both only reachable from there *)
  PROCEDURE InAggregates(): LONGINT;
    VAR box: Box; slots: ARRAY 3 OF Node;
    PROCEDURE Make(v: INTEGER): Node;
      VAR n: Node;
    BEGIN NEW(n); n.value := v; RETURN n
    END Make;
    PROCEDURE Churn;
      VAR temp: Node; i: LONGINT;
    BEGIN
      FOR i := 1 TO 150000 DO NEW(temp) END
    END Churn;
    PROCEDURE Store;
    BEGIN
      box.held := Make(10); slots[0] := Make(20); slots[2] := Make(30)
    END Store;
  BEGIN
    slots[1] := NIL;
    Store; Churn;
    RETURN box.held.value + slots[0].value + slots[2].value
  END InAggregates;

  (* a nested procedure allocating while an enclosing activation, further up a
     recursion, holds the only reference *)
  PROCEDURE Recurse(depth: INTEGER): LONGINT;
    VAR mine: Node; below: LONGINT;
    PROCEDURE Grab;
    BEGIN
      NEW(mine); mine.value := depth
    END Grab;
    PROCEDURE Churn;
      VAR temp: Node; i: LONGINT;
    BEGIN
      FOR i := 1 TO 20000 DO NEW(temp) END
    END Churn;
    PROCEDURE Below(): LONGINT;
    BEGIN
      IF depth < 5 THEN RETURN Recurse(depth + 1) ELSE RETURN 0 END
    END Below;
  BEGIN
    Grab; below := Below(); Churn;
    RETURN below + mine.value
  END Recurse;

  PROCEDURE Main;
    VAR list: Node;
  BEGIN
    Report(1, Local() = 1275);
    list := NIL; ThroughVar(list); Report(2, Sum(list) = 6);
    Report(3, InAggregates() = 60);
    Report(4, Recurse(1) = 15)
  END Main;

BEGIN
  Main
END nestedgc.
