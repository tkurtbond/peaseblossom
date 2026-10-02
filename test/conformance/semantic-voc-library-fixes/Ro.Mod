MODULE Ro;
  (* exports a read-only pointer field and a NIL constant, for
     libraryfixes.mod *)
  TYPE Ptr* = POINTER TO ARRAY 4 OF INTEGER;
    R* = RECORD p-: Ptr END;
    P* = POINTER TO R;
  CONST none* = NIL;
  VAR x-: P;
BEGIN NEW(x); NEW(x.p)
END Ro.
