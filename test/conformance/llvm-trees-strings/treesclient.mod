MODULE treesclient;
  (* PLAN.md Phase 9 step 7: Chapter 11's Trees module, as a library, used
     across a module boundary - string literals passed to an open-array
     value parameter of a bound procedure, names compared and copied
     through pointers to open arrays, the read-only exported name field.
     Each check prints "FAIL nn " on failure; the run ends with "OK". *)
  IMPORT Trees;
  VAR t, found: Trees.Tree;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR msg: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      msg[0] := "F"; msg[1] := "A"; msg[2] := "I"; msg[3] := "L"; msg[4] := " ";
      msg[5] := CHR(ORD("0") + number DIV 10); msg[6] := CHR(ORD("0") + number MOD 10);
      msg[7] := " "; msg[8] := 0X;
      SysWrite(1, msg, 8)
    END
  END Check;

BEGIN
  t := Trees.NewTree();
  t.Insert("mango"); t.Insert("apple"); t.Insert("cherry");
  t.Insert("banana"); t.Insert("apple"); t.Insert("zebra"); t.Insert("kiwi");
  t.Write;
  found := t.Search("kiwi");
  Check(1, found # NIL);
  Check(2, found.name^ = "kiwi");
  Check(3, LEN(found.name^) = 6);
  Check(4, t.Search("plum") = NIL);
  Check(5, t.Search("apple") # NIL);
  Check(6, t.Search("") = t);
  found := t.Search("zebra");
  Check(7, (found # NIL) & (found.Search("zebra") = found) & (found.Search("kiwi") = NIL));
  SysWrite(1, "OK", 2)
END treesclient.
