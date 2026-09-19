MODULE fields;
  (* PLAN.md Phase 9 step 5: operations reaching a variable through a
     pointer - string compare and COPY on a field, INC/INCL, LEN, a chain
     of "." through a cycle, CASE and FOR over a field. Each check prints
     "FAIL nn " on failure; the run ends with "OK". *)
  TYPE
    Named = POINTER TO NamedDesc;
    NamedDesc = RECORD
      name: ARRAY 8 OF CHAR;
      count: INTEGER;
      set: SET;
      flag: BOOLEAN;
      real: REAL;
      next: Named
    END;
    Vec = POINTER TO ARRAY 5 OF INTEGER;
  VAR n, m: Named; v: Vec; i: INTEGER;
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
BEGIN
  NEW(n); NEW(m); NEW(v);
  n.name := "abc"; m.name := "abd";
  Check(1, n.name < m.name);
  Check(2, n.name # m.name);
  Check(3, n.name = "abc");
  COPY("zzz", n.name);
  Check(4, n.name > m.name);
  INC(n.count); INC(n.count, 5);
  Check(5, n.count = 6);
  DEC(n.count);
  Check(6, n.count = 5);
  INCL(n.set, 3); INCL(n.set, 4);
  Check(7, (3 IN n.set) & ~(2 IN n.set));
  n.flag := TRUE; n.real := 2.5;
  Check(8, n.flag & (n.real * 2 = 5.0));
  Check(9, LEN(v^) = 5);
  Check(10, LEN(n.name) = 8);
  FOR i := 0 TO 4 DO v[i] := i END;
  INC(v[2], 10);
  Check(11, v[2] = 12);
  n.next := m; m.next := n;
  Check(12, n.next.next = n);
  Check(13, n.next.next.next.next.name = "zzz");
  CASE n.count OF 5: i := 1 | 6: i := 2 ELSE i := 3 END;
  Check(14, i = 1);
  FOR i := 0 TO n.count DO m.count := i END;
  Check(15, m.count = 5);
  SysWrite(1, "OK", 2)
END fields.
