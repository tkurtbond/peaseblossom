MODULE Ticks;
  IMPORT SYSTEM, Out, AsynchronousTraps, EventFlags, Timers;

  TYPE
    Tick = POINTER TO TickRecord;
    TickRecord = RECORD number: SYSTEM.CARD32; next: Tick END;

  VAR
    ticks: Tick; (* noted by Arrived, newest first, not yet taken *)
    done: SYSTEM.CARD32; (* the event flag the last tick sets *)

  (* an AST routine: notes its tick, and asks for the next until the fifth *)
  PROCEDURE Arrived(number: SYSTEM.CARD32);
    VAR tick: Tick; status: SYSTEM.INT32;
  BEGIN
    NEW(tick); tick.number := number; tick.next := ticks; ticks := tick;
    IF number < 5 THEN
      status := Timers.After(20, Arrived, number + 1)
    ELSE
      status := EventFlags.Set(done)
    END
  END Arrived;

  (* the ticks Arrived has noted since the last Take, oldest first *)
  PROCEDURE Take(): Tick;
    VAR wasEnabled: BOOLEAN; taken, oldestFirst, next: Tick;
  BEGIN
    wasEnabled := AsynchronousTraps.Disable();
    taken := ticks; ticks := NIL;
    AsynchronousTraps.Restore(wasEnabled);
    oldestFirst := NIL;
    WHILE taken # NIL DO
      next := taken.next; taken.next := oldestFirst; oldestFirst := taken; taken := next
    END;
    RETURN oldestFirst
  END Take;

  PROCEDURE Run;
    VAR status: SYSTEM.INT32; finished: BOOLEAN; tick: Tick;
  BEGIN
    status := EventFlags.Get(done);
    status := EventFlags.Clear(done);
    status := Timers.After(20, Arrived, 1);
    Out.String("ticks:");
    REPEAT
      status := Timers.Sleep(30);
      finished := EventFlags.IsSet(done);
      tick := Take();
      WHILE tick # NIL DO
        Out.Char(" "); Out.Card(tick.number, 0); tick := tick.next
      END
    UNTIL finished;
    Out.Ln;
    status := EventFlags.Free(done)
  END Run;

BEGIN
  Run
END Ticks.
