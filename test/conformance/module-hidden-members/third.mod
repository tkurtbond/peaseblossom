MODULE third;
  (* A third module whose record type appears in one of lib's hidden
     fields, so lib's .sym must re-export the IMPORT for its own hidden
     member to resolve. *)
  TYPE
    Stamp* = RECORD when*: LONGINT; who: CHAR END;
END third.
