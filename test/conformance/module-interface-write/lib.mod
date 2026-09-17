MODULE lib;
  (* PLAN.md Phase 7: a representative mix of exported/unexported
     CONST/TYPE (record with a base type, pointer, open array, procedure
     type)/VAR/PROCEDURE/type-bound-PROCEDURE, golden-diffed as the
     .sym file poc -emit-interface writes for this module. *)

  CONST
    Limit* = 100;
    Hidden = 7;
    Greeting* = "hi";
    Flag* = TRUE;

  TYPE
    Base* = RECORD
      tag*: INTEGER
    END;
    Derived* = RECORD (Base)
      value*: INTEGER;
      secret: INTEGER
    END;
    List* = POINTER TO ListNode;
    ListNode = RECORD
      data-: INTEGER;
      next*: List
    END;
    Names* = ARRAY OF INTEGER;
    Callback* = PROCEDURE(x: INTEGER): BOOLEAN;

  VAR
    Counter*: INTEGER;
    ReadOnlyCounter-: INTEGER;
    hidden: INTEGER;

  PROCEDURE (l: List) Sum*(): INTEGER;
  BEGIN
    RETURN l.data
  END Sum;

  PROCEDURE (VAR b: Base) Tag*(): INTEGER;
  BEGIN
    RETURN b.tag
  END Tag;

  PROCEDURE MakeList*(n: INTEGER): List;
  VAR l: List;
  BEGIN
    NEW(l); l.data := n; l.next := NIL;
    RETURN l
  END MakeList;

  PROCEDURE Hidden2(n: INTEGER): INTEGER;
  BEGIN
    RETURN n
  END Hidden2;

END lib.
