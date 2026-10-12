MODULE VaxFieldsUse;
  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md,
     section 16, proposal 7): record field initializers, where records of
     VaxFields' types and this module's get their defaults - module
     variables and locals, in declaration order with the variable
     initializers; NEW of a record, of a fixed array and of an open array;
     an extension of another module's type, an anonymous record, a record
     declared in a procedure whose default uses its constant. A copy gets
     none. FieldsOut prints what each holds, on both backends. *)
  IMPORT F := VaxFields;
  CONST start = 40;
  TYPE
    Labelled* = RECORD (F.Named) label*: CHAR := "L"; size*: LONGINT := start + 2 END;
    Points* = POINTER TO ARRAY 4 OF F.Point;
    Open* = POINTER TO ARRAY OF ARRAY OF F.Named;
  VAR
    n*, copy*: F.Named; h*: F.Holder; seen*: INTEGER := n.serial;
    lab*: Labelled; list*: F.List; points*: Points; open*: Open;
    anonymous*: RECORD flag*: BOOLEAN := TRUE; code*: SHORTINT := -3 END;

  PROCEDURE Make*;
  BEGIN
    NEW(list); NEW(list.next); NEW(points); NEW(open, 2, 3)
  END Make;

  PROCEDURE Local*(VAR before: INTEGER; VAR p: F.Point; VAR v, w: INTEGER);
    CONST base = 100;
    TYPE Inner = RECORD v: INTEGER := base + 5 END;
    VAR first: INTEGER := F.counter; q: F.Point; in: Inner; arr: ARRAY 2 OF Inner;
  BEGIN
    before := first; p := q; v := in.v; w := arr[1].v
  END Local;

  PROCEDURE Copy*;
  BEGIN n.x := 9; copy := n
  END Copy;

END VaxFieldsUse.
