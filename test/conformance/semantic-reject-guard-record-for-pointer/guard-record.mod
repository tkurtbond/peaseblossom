MODULE guardRecord;
  (* On a pointer, a type guard, IS and WITH name a pointer type
     (Oberon2.pdf 8.1, 8.2.5: "T is an extension of the static type of v";
     pointer types adopt their bases' extension relation). A record type
     there was accepted until 2026-09-25 - and inside the guard the pointer
     then had the record type. voc rejects it too (err 86). The last four
     lines, with the pointer type, and a VAR record parameter tested with a
     record type, are accepted. *)
  TYPE
    Node = RECORD value: INTEGER END;
    CenterNode = RECORD (Node) weight: INTEGER END;
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;
  VAR t, u: Tree; b: BOOLEAN; i: INTEGER;

  PROCEDURE Weight(VAR n: Node): INTEGER;
  BEGIN
    IF n IS CenterNode THEN RETURN n(CenterNode).weight ELSE RETURN 0 END
  END Weight;

BEGIN
  b := t IS CenterNode;
  i := t(CenterNode).weight;
  WITH t: CenterNode DO i := 1 END;
  b := t IS CenterTree;
  i := t(CenterTree).weight;
  WITH t: CenterTree DO u := t; i := t^.weight END;
  i := Weight(t^)
END guardRecord.
