MODULE unrelatedCompare;
  (* = and # on pointers need related types (Oberon2.pdf Appendix A: "NIL,
     pointer type T0 or T1", T1 an extension of T0), and on procedure values
     one type ("procedure type T, NIL"); voc: err 100. poc compared any two
     until 2026-09-25. The first two comparisons are errors, the rest are
     accepted: a pointer and an extension of its type, NIL, one procedure
     type, and SYSTEM.PTR with any pointer (poc's extension). *)
  IMPORT SYSTEM;
  TYPE
    A = POINTER TO RECORD x: INTEGER END;
    B = POINTER TO RECORD y: CHAR END;
    Base = POINTER TO BaseDesc; BaseDesc = RECORD END;
    Ext = POINTER TO ExtDesc; ExtDesc = RECORD (BaseDesc) END;
    F = PROCEDURE (x: INTEGER);
    G = PROCEDURE (c: CHAR): BOOLEAN;
  VAR a: A; b: B; base: Base; ext: Ext; f, f2: F; g: G; any: SYSTEM.PTR; t: BOOLEAN;
BEGIN
  t := a = b;
  t := f # g;
  t := base = ext;
  t := ext # base;
  t := a = NIL;
  t := f = f2;
  t := g # NIL;
  t := any = a
END unrelatedCompare.
