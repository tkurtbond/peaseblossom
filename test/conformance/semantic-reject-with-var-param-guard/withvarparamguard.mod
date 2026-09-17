MODULE withVarParamGuard;
  (* A VAR parameter of pointer type is an alias to the caller's own
     storage - some other, later call passing that same actual variable
     by VAR again could reassign it out from under the guard, so
     CheckWithGuard rejects it exactly like a module-qualified guard
     variable (see its own header comment); confirmed against real voc
     2026-09-17, which rejects this shape too (err 245), while a plain
     value (non-VAR) pointer parameter is exempt - see
     semantic-with-value-param-guard, the companion accepting fixture. *)

  TYPE
    Node = RECORD value: INTEGER END;
    CenterNode = RECORD (Node) weight: INTEGER END;
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;

  VAR w: INTEGER;

  PROCEDURE Test(VAR t: Tree);
  BEGIN
    WITH t: CenterTree DO
      w := t.weight
    END
  END Test;

BEGIN
END withVarParamGuard.
