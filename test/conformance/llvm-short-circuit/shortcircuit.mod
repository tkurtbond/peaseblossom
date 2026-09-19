MODULE shortcircuit;
  (* PLAN.md Phase 9 step 5: "&" and OR evaluate their right operand only
     when the left one does not already decide the result (Oberon2.pdf
     Appendix A) - observable now that an operand can have a side effect
     (a call) or trap (an array index, a NIL dereference). Each check
     prints "FAIL nn " on failure; the run ends with "OK". *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: INTEGER
    END;
  VAR
    calls: INTEGER;
    list, p: Node;
    a: ARRAY 4 OF INTEGER;
    i: INTEGER;
    flag: BOOLEAN;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR text: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      text[0] := "F"; text[1] := "A"; text[2] := "I"; text[3] := "L"; text[4] := " ";
      text[5] := CHR(ORD("0") + number DIV 10); text[6] := CHR(ORD("0") + number MOD 10);
      text[7] := " "; text[8] := 0X;
      SysWrite(1, text, 8)
    END
  END Check;

  (* counts how often it runs *)
  PROCEDURE Yes(): BOOLEAN;
  BEGIN
    INC(calls); RETURN TRUE
  END Yes;

  PROCEDURE No(): BOOLEAN;
  BEGIN
    INC(calls); RETURN FALSE
  END No;

BEGIN
  calls := 0;
  flag := No() & Yes();
  Check(1, ~flag & (calls = 1));          (* Yes was not called *)
  flag := Yes() & No();
  Check(2, ~flag & (calls = 3));          (* both were *)
  flag := Yes() OR No();
  Check(3, flag & (calls = 4));           (* No was not called *)
  flag := No() OR Yes();
  Check(4, flag & (calls = 6));
  flag := No() & Yes() OR Yes();          (* (No & Yes) OR Yes: Yes runs once, for the OR *)
  Check(5, flag & (calls = 8));
  flag := Yes() OR No() & No();           (* Yes OR (No & No): neither No runs *)
  Check(6, flag & (calls = 9));
  flag := (No() OR No()) & Yes();
  Check(7, ~flag & (calls = 11));

  (* the right operand would trap: an index out of range, a NIL access *)
  FOR i := 0 TO 3 DO a[i] := i END;
  i := 9;
  Check(8, ~((i < 4) & (a[i] = 0)));
  Check(9, (i >= 4) OR (a[i] = 0));
  i := 2;
  Check(10, (i < 4) & (a[i] = 2));
  p := NIL;
  Check(11, ~((p # NIL) & (p.value = 1)));
  Check(12, (p = NIL) OR (p.value = 1));

  (* the classic loops: stop at NIL, or at the end of the array, before looking further *)
  NEW(list); list.value := 1;
  NEW(list.next); list.next.value := 2;
  NEW(list.next.next); list.next.next.value := 3;
  p := list;
  WHILE (p # NIL) & (p.value < 3) DO p := p.next END;
  Check(13, (p # NIL) & (p.value = 3));
  p := list;
  WHILE (p # NIL) & (p.value < 9) DO p := p.next END;
  Check(14, p = NIL);
  i := 0;
  WHILE (i < 4) & (a[i] < 3) DO INC(i) END;
  Check(15, i = 3);
  i := 0;
  WHILE (i < 4) & (a[i] < 99) DO INC(i) END;
  Check(16, i = 4);
  SysWrite(1, "OK", 2)
END shortcircuit.
