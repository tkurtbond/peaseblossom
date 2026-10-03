MODULE Finish;
  (* A finalizer runs once its object is unreachable, or at the end *)
  IMPORT SYSTEM, GarbageCollectedHeap, Out;
  TYPE Resource = POINTER TO RECORD name: ARRAY 16 OF CHAR END;
  VAR r: Resource;

  PROCEDURE Release(obj: SYSTEM.PTR);
    VAR done: Resource;
  BEGIN
    done := SYSTEM.VAL(Resource, obj);
    Out.String("released "); Out.String(done.name); Out.Ln
  END Release;

BEGIN
  NEW(r); r.name := "the file";
  GarbageCollectedHeap.RegisterFinalizer(r, Release);
  Out.String("working"); Out.Ln
END Finish.
