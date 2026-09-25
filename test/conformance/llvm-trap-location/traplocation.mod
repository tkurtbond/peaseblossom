MODULE traplocation;
  (* Phase 11 C7: poc -trap-location starts every trap message with the
     trap's <file>:<line>:<column> and ends it with the procedure it is in,
     "(in <Module>, module body)" outside any. One case per trap status
     (2..11; 11 with -trap-heap-exhausted too), in the imported module (a
     procedure, a nested one, a type-bound one) and in this module's body -
     an index on a continuation line, a CASE whose branches hold statements.
     test.sh runs each case under both size models; llvm-trap-location's
     expected also shows one case built without the switch. *)
  IMPORT SYSTEM, Modules, Out, GarbageCollectedHeap, traplib;
  TYPE
    Vector = POINTER TO ARRAY OF INTEGER;
    Base = RECORD k: INTEGER END;
    Ext = RECORD (Base) e: INTEGER END;
    BaseP = POINTER TO Base;
    ExtP = POINTER TO Ext;
  VAR
    which: LONGINT; n: traplib.Node; k, x: INTEGER; a: ARRAY 3 OF INTEGER;
    r: LONGREAL; v: Vector; b: BaseP; big: ARRAY 8 OF CHAR; small: ARRAY 4 OF CHAR;

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
  END;
  Out.Int(x, 0); Out.Ln
END traplocation.
