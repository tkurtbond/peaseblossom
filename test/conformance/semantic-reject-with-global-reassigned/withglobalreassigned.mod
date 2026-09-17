MODULE withGlobalReassigned;
  (* CollectProcAssignedNames' whole-module pre-pass (CheckWithGuard's own
     header comment) flags t because Reset assigns it somewhere inside a
     PROCEDURE body - purely static, so this is rejected even though
     Reset is never actually called from the guarded body below;
     confirmed against real voc 2026-09-17, which rejects this same
     shape (err 245) with identical reasoning: reassigned "by non-local
     operations" means reachable through *some* procedure call, not
     necessarily one that provably executes. *)

  TYPE
    Node = RECORD value: INTEGER END;
    CenterNode = RECORD (Node) weight: INTEGER END;
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;

  VAR
    t: Tree;
    plain: Tree;
    w: INTEGER;

  PROCEDURE Reset;
  BEGIN
    NEW(plain);
    t := plain
  END Reset;

BEGIN
  NEW(t);
  WITH t: CenterTree DO
    w := t.weight
  END
END withGlobalReassigned.
