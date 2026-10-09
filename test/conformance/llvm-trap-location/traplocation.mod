MODULE traplocation;
  (* Phase 11 C7: poc -trap-location starts every trap message with the
     trap's <file>:<line>:<column> and ends it with the procedure it is in,
     "(in <Module>, module body)" outside any. One case per trap status
     (2..11; 11 with -trap-heap-exhausted too), in the imported module (a
     procedure, a nested one, a type-bound one) and in this module's body -
     an index on a continuation line, a CASE whose branches hold statements.
     Cases 11 and 12 are a WITH of two guards, the second on its own line:
     no guard holds (status 6), and the second guard's variable is NIL
     (status 4); both trap at the WITH. Cases 13 and 14 dereference and call
     a NIL element (status 4), at the designator, not at its index. test.sh
     runs each case under both size models, and one case without the switch. *)
  IMPORT SYSTEM, Modules, Out, GarbageCollectedHeap, traplib;
  TYPE
    Vector = POINTER TO ARRAY OF INTEGER;
    Base = RECORD k: INTEGER END;
    Ext = RECORD (Base) e: INTEGER END;
    BaseP = POINTER TO Base;
    ExtP = POINTER TO Ext;
    Other = RECORD (Base) o: INTEGER END;
    OtherP = POINTER TO Other;
  VAR
    which: LONGINT; n: traplib.Node; k, x: INTEGER; a: ARRAY 3 OF INTEGER;
    r: LONGREAL; v: Vector; b, e: BaseP; big: ARRAY 8 OF CHAR; small: ARRAY 4 OF CHAR;
    ps: ARRAY 3 OF BaseP; fs: ARRAY 3 OF PROCEDURE (i: INTEGER): INTEGER;
  PROCEDURE Assign(s: ARRAY OF CHAR);
  BEGIN
    small := s
  END Assign;

BEGIN
  Modules.GetIntArg(1, which);
  CASE which OF
    0: x := traplib.Get(7)
  | 1: x := traplib.Get(-1)
  | 2: NEW(n); n.value := 1; x := n.Sum()
  | 3: k := 5;
       x := a[0] +
            a[k]
  | 4: k := 9;
       CASE k OF
         1: x := 1
       | 2: x := 2;
            x := 3
       END
  | 5: NEW(n); x := traplib.Extra(n)
  | 6: NEW(b);
       WITH b: ExtP DO x := 1 END;
       x := 1
  | 7: k := 0; NEW(v, k)
  | 8: r := 1.0D30; x := SHORT(ENTIER(r))
  | 9: big := "abcdefg"; Assign(big)
  | 10: GarbageCollectedHeap.SetChunkSize(8192); GarbageCollectedHeap.SetHeapLimit(65536);
        NEW(v, 100000)
  | 11: NEW(b);
        WITH b: ExtP DO x := 1
        | b: OtherP DO x := 2
        END
  | 12: NEW(b); e := NIL;
        WITH b: ExtP DO x := 1
        | e: ExtP DO x := 2
        END
  | 13: k := 1; NEW(ps[0]);
        x := ps[k]^.k
  | 14: k := 2;
        x := fs[k](1)
  END;
  Out.Int(x, 0); Out.Ln
END traplocation.
