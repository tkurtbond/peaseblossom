MODULE UnresolvedBase;
(* A record extends a type of a module that cannot be imported. Only the
   import is an error: a field or type-bound procedure the record lacks
   may be its base's, so none is reported, and poc does not stop on it
   (it trapped in Types.FindField until Phase 12 step 3, 2026-09-27). A
   record whose bases all resolved still gets the error. *)
  IMPORT Events := NoSuchModule;
  TYPE
    Event = POINTER TO EventDesc;
    EventDesc = RECORD (Events.EventRec) code: INTEGER END;
    Plain = RECORD x: INTEGER END;
  VAR e: Event; p: Plain;
  PROCEDURE (e: Event) Handle; END Handle;
BEGIN
  NEW(e); e.code := 1; e.type := 2; e.Handle; e.Raise;
  p.y := 3
END UnresolvedBase.
