MODULE lib;
  (* Confirms a missing -output-dir directory is a clean, reported write
     failure, not a crash - ModuleInterface.Mod's Write* validates the
     directory via Platform.Chdir before ever calling Files.New, which
     (confirmed against real voc) Halts the whole process on a missing
     directory rather than returning NIL the way Files.Old does. *)

  CONST X* = 1;

END lib.
