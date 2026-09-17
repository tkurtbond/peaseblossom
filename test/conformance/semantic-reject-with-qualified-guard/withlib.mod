MODULE withlib;
  (* Library half of a cross-module WITH-guard-safety conformance test
     (PLAN.md's "Type guards in designators" entry's non-local-operations
     follow-up): an ordinary exported pointer variable, never reassigned
     anywhere in this module - real voc still rejects guarding it from an
     importing module unconditionally (confirmed 2026-09-17), since it
     can't/won't trust another module's procedures, now or after a future
     recompile, from just its .sym interface. The client half in this
     same directory exercises exactly that. *)

  TYPE
    Node* = RECORD value*: INTEGER END;
    CenterNode* = RECORD (Node) weight*: INTEGER END;
    Tree* = POINTER TO Node;
    CenterTree* = POINTER TO CenterNode;

  VAR t*: Tree;

BEGIN
  NEW(t)
END withlib.
