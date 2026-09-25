MODULE traplib;
  (* The imported half of llvm-trap-location: its traps must name this file,
     as poc found it (lib/traplib.mod), and these procedures. *)
  TYPE
    Node* = POINTER TO NodeDesc;
    NodeDesc* = RECORD value*: INTEGER; next*: Node END;
    Wide* = POINTER TO WideDesc;
    WideDesc* = RECORD (NodeDesc) extra*: INTEGER END;
  VAR data: ARRAY 4 OF INTEGER;

  PROCEDURE (n: Node) Sum*(): INTEGER;
  BEGIN
    RETURN n.value + n.next.value
  END Sum;

  PROCEDURE Get*(i: INTEGER): INTEGER;
    PROCEDURE Check(j: INTEGER);
    BEGIN
      ASSERT(j >= 0, 20)
    END Check;
  BEGIN
    Check(i);
    RETURN data[i]
  END Get;

  PROCEDURE Extra*(n: Node): INTEGER;
  BEGIN
    RETURN n(Wide).extra
  END Extra;
END traplib.
