MODULE SevenLib;
  (* vax-options-files (doc/developer/vax-macro32-backend.md, section
     13.3): the module of the library SEVEN, whose manifest records the
     lines of the options file it was made with. *)

  PROCEDURE Seven*(): LONGINT;
  BEGIN
    RETURN 7
  END Seven;

END SevenLib.
