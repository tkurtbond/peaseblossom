MODULE TaskSync;
  (* On VAX/VMS, the program of llvm-tasks-sync.
     Tasks' conditions and mutexes (doc/developer/tasks.md, Phase 9): a
     bounded buffer with two conditions, Mesa's rule (a woken task tests
     again), Signal waking the longest waiter, Broadcast, Signal with no
     waiter, and a mutex held across a Send, handed to its waiters in
     order. *)
  IMPORT Tasks, Out;

  CONST size = 3;

  TYPE
    Producer = POINTER TO RECORD (Tasks.TaskDesc) first, last: INTEGER END;
    Consumer = POINTER TO RECORD (Tasks.TaskDesc) name: CHAR; count: INTEGER END;
    Waiter = POINTER TO RECORD (Tasks.TaskDesc) name: CHAR END;
    Writer = POINTER TO RECORD (Tasks.TaskDesc) name: CHAR END;
    Thief = POINTER TO RECORD (Tasks.TaskDesc) END;
    Number = POINTER TO RECORD (Tasks.MessageDesc) value: LONGINT END;

  VAR
    buffer: ARRAY size OF INTEGER;
    head, count: INTEGER;
    notFull, notEmpty, gate: Tasks.Condition;
    open: BOOLEAN;
    lock: Tasks.Mutex;
    line: Tasks.Channel;
    p1, p2: Producer; c1, c2: Consumer;
    w: ARRAY 4 OF Waiter;
    writer: ARRAY 3 OF Writer;
    thief: Thief;
    m: Tasks.Message;
    i: INTEGER;
    retries: INTEGER;

  PROCEDURE Put(x: INTEGER);
  BEGIN
    WHILE count = size DO Tasks.Wait(notFull) END;
    buffer[(head + count) MOD size] := x; INC(count);
    Tasks.Signal(notEmpty)
  END Put;

  PROCEDURE Get(): INTEGER;
    VAR x: INTEGER;
  BEGIN
    WHILE count = 0 DO INC(retries); Tasks.Wait(notEmpty) END;
    x := buffer[head]; head := (head + 1) MOD size; DEC(count);
    Tasks.Signal(notFull);
    RETURN x
  END Get;

  PROCEDURE (p: Producer) Run*;
    VAR i: INTEGER;
  BEGIN
    FOR i := p.first TO p.last DO Put(i) END
  END Run;

  PROCEDURE (c: Consumer) Run*;
    VAR i, x: INTEGER;
  BEGIN
    FOR i := 1 TO c.count DO x := Get(); Out.Char(c.name); Out.Int(x, 0); Out.Char(" ") END
  END Run;

  PROCEDURE (w: Waiter) Run*;
  BEGIN
    Out.Char(w.name); Out.String(" waits; ");
    WHILE ~open DO Tasks.Wait(gate) END;
    Out.Char(w.name); Out.String(" through; ")
  END Run;

  (* takes what a Signal made available before the woken task runs *)
  PROCEDURE (t: Thief) Run*;
  BEGIN
    IF count > 0 THEN DEC(count); Out.String("thief took one; ") END
  END Run;

  PROCEDURE (w: Writer) Run*;
    VAR n: Number; i: INTEGER;
  BEGIN
    Tasks.Lock(lock);
    Out.Char(w.name); Out.String(" holds; ");
    FOR i := 1 TO 2 DO
      NEW(n); n.value := (ORD(w.name) - ORD("a") + 1) * 10 + i;
      Tasks.Send(line, n)  (* blocks, holding the lock *)
    END;
    Out.Char(w.name); Out.String(" unlocks; ");
    Tasks.Unlock(lock)
  END Run;

BEGIN
  Out.String("-- a bounded buffer, two producers, two consumers"); Out.Ln;
  NEW(p1); p1.first := 1; p1.last := 6; Tasks.Start(p1, Tasks.DefaultStackSize);
  NEW(p2); p2.first := 101; p2.last := 106; Tasks.Start(p2, Tasks.DefaultStackSize);
  NEW(c1); c1.name := "x"; c1.count := 6; Tasks.Start(c1, Tasks.DefaultStackSize);
  NEW(c2); c2.name := "y"; c2.count := 6; Tasks.Start(c2, Tasks.DefaultStackSize);
  Tasks.Join(c1); Tasks.Join(c2); Tasks.Join(p1); Tasks.Join(p2); Out.Ln;
  Out.String("left: "); Out.Int(count, 0); Out.Ln;

  Out.String("-- Mesa: a woken task tests again"); Out.Ln;
  count := 0; head := 0; retries := 0;
  NEW(c1); c1.name := "z"; c1.count := 1; Tasks.Start(c1, Tasks.DefaultStackSize);
  Tasks.Yield;            (* z waits on notEmpty *)
  NEW(thief); Tasks.Start(thief, Tasks.DefaultStackSize);
  buffer[0] := 7; count := 1; Tasks.Signal(notEmpty);
  Tasks.Yield;            (* z runs after the thief, finds nothing, waits again *)
  Out.String("z waited "); Out.Int(retries, 0); Out.String(" times; ");
  buffer[0] := 8; count := 1; head := 0; Tasks.Signal(notEmpty);
  Tasks.Join(c1); Out.Ln;

  Out.String("-- Signal wakes the longest waiter, Broadcast the rest"); Out.Ln;
  Tasks.Signal(gate); Out.String("a Signal with no waiter is lost; ");
  open := FALSE;
  FOR i := 0 TO 3 DO NEW(w[i]); w[i].name := CHR(ORD("a") + i); Tasks.Start(w[i], Tasks.DefaultStackSize) END;
  Tasks.Yield; Out.Ln;
  open := TRUE;
  Tasks.Signal(gate); Tasks.Yield; Out.Ln;
  Tasks.Broadcast(gate);
  FOR i := 0 TO 3 DO Tasks.Join(w[i]) END; Out.Ln;

  Out.String("-- a mutex held across a Send"); Out.Ln;
  line := Tasks.NewChannel(0);
  FOR i := 0 TO 2 DO NEW(writer[i]); writer[i].name := CHR(ORD("a") + i); Tasks.Start(writer[i], Tasks.DefaultStackSize) END;
  FOR i := 1 TO 6 DO
    IF Tasks.Receive(line, m) THEN Out.Int(m(Number).value, 0); Out.String("; ") END
  END;
  FOR i := 0 TO 2 DO Tasks.Join(writer[i]) END; Out.Ln;
  Tasks.Lock(lock); Tasks.Unlock(lock); Out.String("free again"); Out.Ln
END TaskSync.
