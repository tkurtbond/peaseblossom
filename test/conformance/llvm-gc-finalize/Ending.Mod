MODULE Ending;
  (* registers two objects whose finalizers print their values, for the
     programs that end in each way *)
  IMPORT SYSTEM, Out, GarbageCollectedHeap;
  TYPE Node* = POINTER TO RECORD value*: LONGINT END;
  VAR one, two: Node;
  PROCEDURE Print(obj: SYSTEM.PTR);
    VAR n: Node;
  BEGIN n := SYSTEM.VAL(Node, obj); Out.String("finalized "); Out.Int(n.value, 0); Out.Ln
  END Print;
  PROCEDURE Register*;
  BEGIN
    NEW(one); one.value := 1; GarbageCollectedHeap.RegisterFinalizer(one, Print);
    NEW(two); two.value := 2; GarbageCollectedHeap.RegisterFinalizer(two, Print)
  END Register;
END Ending.
