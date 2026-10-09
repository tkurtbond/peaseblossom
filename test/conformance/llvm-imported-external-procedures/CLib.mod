MODULE CLib;
  (* Exported external procedures: the .sym keeps each one's calling
     convention and linkage name, so an importer calls the C function
     (Phase 14's "Ongoing bug fixing" 1) *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "strlen"] Length*(s: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C"] abs*(x: SYSTEM.INT32): SYSTEM.INT32;

END CLib.
