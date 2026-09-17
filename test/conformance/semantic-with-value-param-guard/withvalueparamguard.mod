MODULE withValueParamGuard;
  (* A value (non-VAR) parameter of pointer type holds its own private
     copy of the pointer - no other code can reassign it out from under
     the guard, so it's exempt from CheckWithGuard's non-local-operations
     safety check (see that procedure's own header comment); confirmed
     against real voc 2026-09-17, which accepts this same shape. The
     companion rejecting fixture, semantic-reject-with-var-param-guard,
     is identical except for the VAR keyword. *)

  TYPE
    Node = RECORD value: INTEGER END;
    CenterNode = RECORD (Node) weight: INTEGER END;
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;

  VAR w: INTEGER;

  PROCEDURE Test(t: Tree);
  BEGIN
    WITH t: CenterTree DO
      w := t.weight
    END
  END Test;

BEGIN
END withValueParamGuard.
