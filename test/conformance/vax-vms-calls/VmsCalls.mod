MODULE VmsCalls;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1,
     proposal 8): real VMS routines called through ["VMS"] declarations,
     one for each way an argument is passed - a string in and a string
     out by descriptor, with the resultant length; an item list and an I/O
     status block by reference, from VmsArguments; an argument omitted by
     NIL; a quadword by reference, read only, from a variable and from a
     constant; Oberon procedures VMS calls back; and an array of longwords
     by reference as an ARRAY OF SYSTEM.BYTE. Run with the logical name
     POC_VMSCALLS_LNM defined in the process table (guest-run.com). *)
  IMPORT SYSTEM, Out, VmsArguments;

  CONST
    localSymbol = 1; (* LIB$K_CLI_LOCAL_SYM *)
    lnmString = 2; (* LNM$_STRING *)
    jpiUsername = 514; (* JPI$_USERNAME *)
    oneMinute = -600000000; (* a delta time, in 100-nanosecond units *)

  TYPE
    (* a node of LIB$INSERT_TREE's tree: its 10-byte header, then the key *)
    Node = RECORD
      left, right: SYSTEM.ADDRESS;
      reserved: SYSTEM.INT16;
      key: SYSTEM.INT32
    END;
    Compare = PROCEDURE (VAR symbol: SYSTEM.INT32; node, data: SYSTEM.ADDRESS): LONGINT;
    Allocate = PROCEDURE (VAR symbol: SYSTEM.INT32; VAR newNode: SYSTEM.ADDRESS; data: SYSTEM.ADDRESS): LONGINT;
    Action = PROCEDURE (node, data: SYSTEM.ADDRESS): LONGINT;

  VAR
    status: LONGINT;
    value: ARRAY 64 OF CHAR;
    length, usernameLength: SYSTEM.INT16;
    table: LONGINT;
    items: ARRAY 2 OF VmsArguments.ItemListEntry3;
    iosb: VmsArguments.IOStatusBlock;
    username: ARRAY 12 OF CHAR;
    time: HUGEINT;
    nodes: ARRAY 8 OF Node;
    nodeCount: INTEGER;
    head, newNode: SYSTEM.ADDRESS;
    keys: ARRAY 4 OF SYSTEM.INT32;
    i: INTEGER;
    parameters: ARRAY 2 OF SYSTEM.INT32;

  PROCEDURE ["VMS", "LIB$SET_SYMBOL"] SetSymbol(symbol-, valueString-: ARRAY OF CHAR;
                                                table-: LONGINT): LONGINT;
  PROCEDURE ["VMS", "LIB$GET_SYMBOL"] GetSymbol(symbol-: ARRAY OF CHAR; VAR resultant: ARRAY OF CHAR;
                                                VAR resultantLength: SYSTEM.INT16;
                                                VAR tableType: LONGINT): LONGINT;
  PROCEDURE ["VMS", "LIB$DELETE_SYMBOL"] DeleteSymbol(symbol-: ARRAY OF CHAR; table-: LONGINT): LONGINT;
  PROCEDURE ["VMS", "SYS$TRNLNM"] TranslateName(attributes-: LONGINT; tableName-, logicalName-: ARRAY OF CHAR;
                                                accessMode-: SYSTEM.INT8;
                                                itemList-: ARRAY OF VmsArguments.ItemListEntry3): LONGINT;
  PROCEDURE ["VMS", "SYS$GETJPIW"] GetJobProcessInfo(eventFlag: LONGINT; VAR processId: LONGINT;
                                                     processName-: ARRAY OF CHAR;
                                                     itemList-: ARRAY OF VmsArguments.ItemListEntry3;
                                                     VAR ioStatus: VmsArguments.IOStatusBlock;
                                                     astRoutine, astParameter: SYSTEM.ADDRESS): LONGINT;
  PROCEDURE ["VMS", "SYS$BINTIM"] BinaryTime(text-: ARRAY OF CHAR; VAR time: HUGEINT): LONGINT;
  PROCEDURE ["VMS", "SYS$ASCTIM"] AsciiTime(VAR textLength: SYSTEM.INT16; VAR text: ARRAY OF CHAR;
                                            time-: HUGEINT; convertFlag: LONGINT): LONGINT;
  PROCEDURE ["VMS", "LIB$INSERT_TREE"] InsertTree(VAR treeHead: SYSTEM.ADDRESS; symbol-: SYSTEM.INT32;
                                                  flags-: LONGINT; compare: Compare; allocate: Allocate;
                                                  VAR newNode: SYSTEM.ADDRESS;
                                                  data: SYSTEM.ADDRESS): LONGINT;
  PROCEDURE ["VMS", "LIB$TRAVERSE_TREE"] TraverseTree(VAR treeHead: SYSTEM.ADDRESS; action: Action;
                                                      data: SYSTEM.ADDRESS): LONGINT;
  PROCEDURE ["VMS", "SYS$FAOL"] FormatList(control-: ARRAY OF CHAR; VAR outputLength: SYSTEM.INT16;
                                           VAR output: ARRAY OF CHAR;
                                           VAR parameterList: ARRAY OF SYSTEM.BYTE): LONGINT;

  (* a condition value as DCL writes one, %X and 8 digits *)
  PROCEDURE Status(text: ARRAY OF CHAR; s: LONGINT);
  BEGIN
    Out.String(text); Out.String("%X"); Out.Hex(s, 8)
  END Status;

  (* s's first n characters, in brackets, then the status *)
  PROCEDURE Show(what: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; n: LONGINT);
  BEGIN
    IF (n >= 0) & (n < LEN(s)) THEN s[n] := 0X END;
    Out.String(what); Out.String(" ["); Out.String(s); Status("] status ", status); Out.Ln
  END Show;

  PROCEDURE CompareKey(VAR symbol: SYSTEM.INT32; node, data: SYSTEM.ADDRESS): LONGINT;
    VAR key: SYSTEM.INT32;
  BEGIN
    SYSTEM.GET(node + 12, key);
    RETURN symbol - key
  END CompareKey;

  PROCEDURE AllocateNode(VAR symbol: SYSTEM.INT32; VAR newNode: SYSTEM.ADDRESS; data: SYSTEM.ADDRESS): LONGINT;
  BEGIN
    nodes[nodeCount].key := symbol;
    newNode := SYSTEM.ADR(nodes[nodeCount]); INC(nodeCount);
    RETURN 1
  END AllocateNode;

  PROCEDURE ShowNode(node, data: SYSTEM.ADDRESS): LONGINT;
    VAR key: SYSTEM.INT32;
  BEGIN
    SYSTEM.GET(node + 12, key);
    Out.Char(" "); Out.Int(key, 0);
    RETURN 1
  END ShowNode;

BEGIN
  (* strings by descriptor: in, then out with the resultant length;
     table- omitted by NIL, so LIB$SET_SYMBOL's local table *)
  status := SetSymbol("POC_VMSCALLS", "from poc", NIL);
  table := 0; value := "untouched";
  status := GetSymbol("POC_VMSCALLS", value, length, table);
  Show("symbol", value, length); Out.String("length "); Out.Int(length, 0);
  Out.String(" table "); Out.Int(table, 0); Out.Ln;
  value := "poc_vmscalls"; (* an input described up to its 0X *)
  status := GetSymbol(value, value, length, table);
  Show("symbol again", value, length);
  status := DeleteSymbol("POC_VMSCALLS", localSymbol);
  status := GetSymbol("POC_VMSCALLS", value, length, table);
  Status("deleted: ", status); Out.Ln;

  (* an item list, the access mode omitted by NIL *)
  VmsArguments.SetItem(items, 0, lnmString, value, length);
  VmsArguments.EndList(items, 1);
  status := TranslateName(0, "LNM$PROCESS", "POC_VMSCALLS_LNM", NIL, items);
  Show("logical name", value, length);

  (* an item list and an I/O status block; the process id and name
     omitted by NIL, so this process *)
  VmsArguments.SetItem(items, 0, jpiUsername, username, usernameLength);
  status := GetJobProcessInfo(0, NIL, NIL, items, iosb, 0, 0);
  Show("username", username, usernameLength);
  Status("I/O status ", iosb.status); Out.Ln;

  (* a quadword by reference, read only: a variable, then a constant *)
  status := BinaryTime("14-OCT-2026 12:34:56.78", time);
  Status("binary time status ", status); Out.Ln;
  status := AsciiTime(length, value, time, 0);
  Show("time", value, length);
  status := AsciiTime(length, value, oneMinute, 0);
  Show("delta", value, length);

  (* callbacks: LIB$INSERT_TREE calls CompareKey and AllocateNode,
     LIB$TRAVERSE_TREE ShowNode *)
  keys[0] := 5; keys[1] := 2; keys[2] := 8; keys[3] := 1;
  FOR i := 0 TO 3 DO
    status := InsertTree(head, keys[i], 0, CompareKey, AllocateNode, newNode, 0)
  END;
  Status("tree, status ", status); Out.String(":");
  status := TraverseTree(head, ShowNode, 0);
  Out.Ln; Status("traversed, status ", status); Out.Ln;

  (* an array of longwords by reference *)
  parameters[0] := 42; parameters[1] := 255;
  status := FormatList("!UL and !XL", length, value, parameters);
  Show("formatted", value, length)
END VmsCalls.
