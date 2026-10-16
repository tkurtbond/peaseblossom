MODULE BalancedTrees;

  (* Balanced binary trees of the program's records, kept by LIB$INSERT_TREE,
     LIB$LOOKUP_TREE and LIB$TRAVERSE_TREE (doc/developer/vms-sdl-interfaces.md,
     part 10, proposal 3; VMS RTL Library (LIB$) Manual, LIB-237).

     A LIB$ node begins with a 10-byte header, two absolute addresses and
     a word (LIB-240), which is what NodeDesc is: an object's address is
     its first field's. A program extends NodeDesc with its key and data,
     makes a node by NEW and fills it, and Insert links it in. LIB$ writes
     left, right and balance, and the collector traces left and right as
     it does any pointer field, so a node lives as long as its tree.

     The program's Compare and Action reach LIB$'s callbacks through a
     record in this module's frame, whose address is the symbol LIB$
     passes them unchanged; LIB$LOOKUP_TREE has no user-data. The module
     keeps nothing of its own between calls. LIB$INSERT_TREE does not
     call its allocate routine for a duplicate it refuses
     (vms-sdl-interfaces.md, "Part 10 done"). *)

  IMPORT SYSTEM, LIBDEF, SSDEF;

  TYPE
    Node* = POINTER TO NodeDesc;
    NodeDesc* = RECORD
      left, right: Node; (* LIB$'s links *)
      balance: SYSTEM.INT16 (* LIB$'s, which reserves it *)
    END;

    Tree* = RECORD
      root: Node (* LIB$'s tree head, NIL when empty *)
    END;

    (* negative, 0 or positive as a comes before, with or after b *)
    Compare* = PROCEDURE (a, b: Node): LONGINT;
    (* called for each node in key order; FALSE stops the walk *)
    Action* = PROCEDURE (node: Node): BOOLEAN;

    (* what LIB$'s callbacks are given: LIB$INSERT_TREE's and
       LIB$LOOKUP_TREE's symbol, LIB$TRAVERSE_TREE's user data *)
    Probe = RECORD
      node: Node; (* the node inserted, or the key looked for *)
      compare: Compare;
      action: Action;
      stopped: BOOLEAN (* whether action has returned FALSE *)
    END;
    ProbePointer = POINTER TO Probe;

    (* LIB$'s callbacks, as they are called *)
    CompareRoutine = PROCEDURE (probe: ProbePointer; node: Node): SYSTEM.INT32;
    AllocateRoutine = PROCEDURE (probe: ProbePointer; VAR newNode: Node): SYSTEM.INT32;
    ActionRoutine = PROCEDURE (node: Node; probe: ProbePointer): SYSTEM.INT32;

  (* LIB_ROUTINES' declarations with the tree head a Node and the routines
     typed; the symbol is a Probe's address *)
  PROCEDURE ["VMS", "LIB$INSERT_TREE"] InsertTree(VAR treehead: Node; symbol: SYSTEM.ADDRESS;
    flags-: SYSTEM.CARD32; compare: CompareRoutine; allocate: AllocateRoutine;
    VAR newNode: Node; userData: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$LOOKUP_TREE"] LookupTree(VAR treehead: Node; symbol: SYSTEM.ADDRESS;
    compare: CompareRoutine; VAR newNode: Node): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$TRAVERSE_TREE"] TraverseTree(VAR treehead: Node; action: ActionRoutine;
    userData: SYSTEM.ADDRESS): SYSTEM.INT32;

  (* LIB$'s compare routine: probe's node against node, by probe's Compare *)
  PROCEDURE CompareNode(probe: ProbePointer; node: Node): SYSTEM.INT32;
    VAR result: LONGINT;
  BEGIN
    result := probe.compare(probe.node, node);
    IF result < 0 THEN RETURN -1 ELSIF result > 0 THEN RETURN 1 ELSE RETURN 0 END
  END CompareNode;

  (* LIB$'s allocate routine: the node the program made *)
  PROCEDURE AllocateNode(probe: ProbePointer; VAR newNode: Node): SYSTEM.INT32;
  BEGIN
    newNode := probe.node;
    RETURN LIBDEF.LIB$_NORMAL
  END AllocateNode;

  (* LIB$'s action routine: probe's Action. A failure status stops
     LIB$TRAVERSE_TREE, which returns it ("Part 10 done") *)
  PROCEDURE VisitNode(node: Node; probe: ProbePointer): SYSTEM.INT32;
    VAR status: SYSTEM.INT32;
  BEGIN
    IF probe.action(node) THEN status := LIBDEF.LIB$_NORMAL
    ELSE probe.stopped := TRUE; status := SSDEF.SS$_ABORT
    END;
    RETURN status
  END VisitNode;

  (* node, made and filled by the program, put in tree by compare. With
     duplicates FALSE and a node equal to it there already, the status is
     LIB$_KEYALRINS, found that node and node not linked in; otherwise
     LIB$_NORMAL, and found is node. compare is not called for the first
     node of a tree *)
  PROCEDURE Insert*(VAR tree: Tree; node: Node; compare: Compare; duplicates: BOOLEAN;
                    VAR found: Node): SYSTEM.INT32;
    VAR probe: Probe; flags: SYSTEM.CARD32;
  BEGIN
    probe.node := node; probe.compare := compare;
    IF duplicates THEN flags := 1 ELSE flags := 0 END;
    found := NIL;
    RETURN InsertTree(tree.root, SYSTEM.ADR(probe), flags, CompareNode, AllocateNode, found, 0)
  END Insert;

  (* the node of tree that compare finds equal to key, a node of the
     program's type with its key filled, or NIL *)
  PROCEDURE Lookup*(VAR tree: Tree; key: Node; compare: Compare): Node;
    VAR probe: Probe; found: Node; status: SYSTEM.INT32;
  BEGIN
    probe.node := key; probe.compare := compare;
    found := NIL;
    status := LookupTree(tree.root, SYSTEM.ADR(probe), CompareNode, found);
    IF ~ODD(status) THEN found := NIL END;
    RETURN found
  END Lookup;

  (* action called for each node of tree in key order, until it returns
     FALSE; LIB$_NORMAL either way *)
  PROCEDURE Traverse*(VAR tree: Tree; action: Action): SYSTEM.INT32;
    VAR probe: Probe; status: SYSTEM.INT32;
  BEGIN
    probe.action := action; probe.stopped := FALSE;
    status := TraverseTree(tree.root, VisitNode, SYSTEM.ADR(probe));
    IF probe.stopped THEN status := LIBDEF.LIB$_NORMAL END;
    RETURN status
  END Traverse;

  (* whether tree has no nodes *)
  PROCEDURE Empty*(VAR tree: Tree): BOOLEAN;
  BEGIN
    RETURN tree.root = NIL
  END Empty;

END BalancedTrees.
