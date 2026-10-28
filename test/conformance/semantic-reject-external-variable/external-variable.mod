MODULE ExternalVariable;
  (* semantic-reject-external-variable (doc/developer/language-extensions.md,
     "External variables"): an external variable is declared only at module
     level, with a known convention, one identifier to a linkage name, and
     no pointer the collector traces anywhere in its type. *)
  IMPORT SYSTEM;

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node END;
    Holder = RECORD count: INTEGER; items: ARRAY 2 OF Node END;
    Callback = PROCEDURE (x: INTEGER);

  VAR
    ["C", "two_names"] first, second: SYSTEM.INT32;
    ["Pascal"] pascalCounter: SYSTEM.INT32;
    ["C"] head: Node;
    ["C"] holder: Holder;
    ["C"] untraced: SYSTEM.PTR;
    ["C"] address: SYSTEM.ADDRESS;
    ["C"] callback: Callback;
    ["C"] opterr, optind: SYSTEM.INT32;

  PROCEDURE P;
    VAR ["C"] local: SYSTEM.INT32;
  BEGIN
    local := 1
  END P;

END ExternalVariable.
