MODULE VaxPtrLib;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, items 3 and 4): imported by VaxPointers. Item is exported, the
     record it is bound to is not, so its descriptor is global for the
     importer's NEW. *)
  TYPE
    Item* = POINTER TO ItemDesc;
    ItemDesc = RECORD key*: LONGINT; link*: Item END;

  PROCEDURE Make*(k: LONGINT): Item;
    VAR p: Item;
  BEGIN
    NEW(p); p.key := k; p.link := NIL;
    RETURN p
  END Make;
END VaxPtrLib.
