MODULE VmsServices;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1): ["VMS"]
     procedures exported, so that an importer passes NIL to them too *)
  IMPORT SYSTEM;
  TYPE Action* = PROCEDURE (node, data: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$TRNLNM"] TranslateName*(attributes-: SYSTEM.INT32; table-, name-: ARRAY OF CHAR;
                                                 accessMode-: SYSTEM.INT8; items-: ARRAY OF SYSTEM.BYTE): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$TRAVERSE_TREE"] TraverseTree*(VAR head: SYSTEM.ADDRESS; action: Action;
                                                       data: SYSTEM.ADDRESS): SYSTEM.INT32;
END VmsServices.
