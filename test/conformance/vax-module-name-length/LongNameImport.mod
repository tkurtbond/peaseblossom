MODULE LongNameImport;
  (* PLAN.md Phase 16 step 4: an import whose name is too long for the VAX
     is refused before its .sym is written *)
  IMPORT ABCDEFGHIJKLMNOPQRSTUVWXYZa;
END LongNameImport.
