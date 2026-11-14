MODULE Tasks;
  (* Cooperative tasks, conditions, mutexes and channels over Coroutines
     (doc/developer/tasks.md; AGENTS.md, "Tasks"). The same source on both
     back ends; what differs is in TaskWaiting.

     A task is an extension of TaskDesc whose Run is its body. Start gives
     it a stack of its own and puts it at the end of the run queue; it runs
     when the running task blocks. Returning from Run ends the task, and its
     stack is given back. The main program is a task too.

         TYPE
           Worker = POINTER TO RECORD (Tasks.TaskDesc) n: LONGINT; out: Tasks.Channel END;
           Result = POINTER TO RECORD (Tasks.MessageDesc) value: LONGINT END;

         PROCEDURE (w: Worker) Run*;
           VAR r: Result;
         BEGIN
           NEW(r); r.value := w.n * w.n; Tasks.Send(w.out, r)
         END Run;

     An override of Run must be exported, as the base procedure is.

     SCHEDULING. Nothing preempts: a task runs until it makes a call that
     can block (Yield, Join, Wait, Lock, Send, Receive, Select), and only
     then may another run, so code between two such calls is atomic. A
     task that blocks switches straight to the first ready task, in the
     order they became ready; Yield puts the running task at the end. A
     blocking call, I/O included, of any other module stops every task.
     The program ends when the main module's body ends: tasks still
     running are abandoned (their Runs do not finish), so Join is how to
     wait for one.

     CONDITIONS AND MUTEXES. A zeroed Condition or Mutex is ready to use;
     pass them by VAR, never copy them. A condition is Mesa's: a woken task
     tests again, WHILE ~ok DO Tasks.Wait(c) END. Signal wakes the task
     that has waited longest. Code between switches is atomic already, so
     a Mutex is needed only around a region that blocks.

     CHANNELS. A message is an extension of MessageDesc, unpacked by a type
     guard, and NIL is a message too. A channel of capacity 0 hands each
     message from a sender to a receiver; one of capacity n holds up to n.
     After Close, Receive takes the messages still held, then returns
     FALSE.

     TRAPS. When no task is ready and nothing can make one ready, the
     program traps (19), "all tasks are blocked". Misuse traps (20): an
     Unlock of a mutex the running task does not hold, a Join of the
     running task, a Send on a closed channel (also one waiting when the
     channel is closed), a Close of a channel already closed, a Start of a
     task already started, NewChannel with a negative capacity. A call
     that blocks traps (17) in a finalizer, as Transfer does there; on
     LLVM in a signal handler too. On VAX/VMS a call that blocks at AST
     level is undefined.

     RULES the program keeps, which nothing checks:
     - A program that imports Tasks may use Coroutines only inside one
       task, between coroutines Tasks does not own, and must be back on
       that task's own coroutine before it calls Tasks again.
     - A task blocked for good keeps its stack until the program ends: one
       waiting on a channel nothing else can reach is a leak. *)

  IMPORT Coroutines, TaskWaiting;

  CONST
    DefaultStackSize* = Coroutines.DefaultStackSize;
    (* a task's states *)
    notStarted = 0; ready = 1; running = 2; blocked = 3; finished = 4;

  TYPE
    Task* = POINTER TO TaskDesc;
    Message* = POINTER TO MessageDesc;
    MessageDesc* = RECORD END;
    Channel* = POINTER TO ChannelDesc;

    (* tasks in the order they joined, linked through next *)
    TaskQueue = RECORD first, last: Task END;

    (* a task waiting in a channel's queue: one for each channel of a
       Select, the task's own for a Send or Receive *)
    Waiter = POINTER TO WaiterDesc;
    WaiterDesc = RECORD
      task: Task;
      channel: Channel;
      message: Message;
      index: LONGINT;      (* in Select's array *)
      delivered: BOOLEAN;  (* FALSE: woken by Close *)
      queued: BOOLEAN;
      next, previous: Waiter;  (* in the channel's queue *)
      sibling: Waiter      (* the same Select's others, or the task's spares *)
    END;
    WaiterQueue = RECORD first, last: Waiter END;

    TaskDesc* = RECORD
      coroutine: Coroutines.Coroutine;
      state: INTEGER;
      next: Task;          (* in the run queue or a queue of waiting tasks *)
      joiners: TaskQueue;
      waiter: Waiter;      (* its own, for a Send or a Receive *)
      spares: Waiter;      (* for Select *)
      fired: Waiter        (* the waiter that woke it; NIL while it waits *)
    END;

    Condition* = RECORD waiting: TaskQueue END;
    Mutex* = RECORD holder: Task; waiting: TaskQueue END;

    Messages = POINTER TO ARRAY OF Message;
    ChannelDesc* = RECORD
      buffer: Messages;
      capacity, head, count: LONGINT;
      closed: BOOLEAN;
      receivers, senders: WaiterQueue
    END;

  VAR
    mainTask, current: Task;
    runQueue: TaskQueue;
    (* a task that has ended, whose stack the next task to run gives back:
       Coroutines.Free of the running coroutine traps *)
    endedTask: Task;

  (* The body: what the task does. Returning ends the task. *)
  PROCEDURE (t: Task) Run*;
  END Run;

  PROCEDURE Append(VAR q: TaskQueue; t: Task);
  BEGIN
    t.next := NIL;
    IF q.first = NIL THEN q.first := t ELSE q.last.next := t END;
    q.last := t
  END Append;

  PROCEDURE Remove(VAR q: TaskQueue): Task;
    VAR t: Task;
  BEGIN
    t := q.first;
    IF t # NIL THEN
      q.first := t.next;
      IF q.first = NIL THEN q.last := NIL END;
      t.next := NIL
    END;
    RETURN t
  END Remove;

  PROCEDURE MakeReady(t: Task);
  BEGIN
    t.state := ready;
    Append(runQueue, t)
  END MakeReady;

  (* The running task waits in a queue of its own *)
  PROCEDURE WaitIn(VAR q: TaskQueue);
  BEGIN
    current.state := blocked;
    Append(q, current)
  END WaitIn;

  (* The next task to run *)
  PROCEDURE NextReady(): Task;
    VAR t: Task;
  BEGIN
    t := Remove(runQueue);
    IF t = NIL THEN TaskWaiting.Deadlock END;
    RETURN t
  END NextReady;

  PROCEDURE FreeFinished;
  BEGIN
    IF endedTask # NIL THEN
      Coroutines.Free(endedTask.coroutine);
      endedTask := NIL
    END
  END FreeFinished;

  (* The running task has put itself where something will make it ready
     again, or in the run queue: runs the next ready task, if that is not
     the running one *)
  PROCEDURE Block;
    VAR old, next: Task;
  BEGIN
    old := current;
    next := NextReady();
    next.state := running;
    IF next # old THEN
      current := next;
      Coroutines.TransferForTasks(old.coroutine, next.coroutine);
      FreeFinished
    END
  END Block;

  (* Every task's coroutine body *)
  PROCEDURE Trampoline;
    VAR t, joiner, next: Task;
  BEGIN
    FreeFinished;
    t := current;
    t.Run;
    t.state := finished;
    joiner := Remove(t.joiners);
    WHILE joiner # NIL DO MakeReady(joiner); joiner := Remove(t.joiners) END;
    endedTask := t;
    next := NextReady();
    next.state := running;
    current := next;
    Coroutines.TransferForTasks(t.coroutine, next.coroutine)
    (* never resumed: its stack is freed *)
  END Trampoline;

  (* Starts t with a stack of stackSize bytes (Coroutines.Init's rules;
     DefaultStackSize is the recommendation): t runs when it reaches the
     front of the run queue. *)
  PROCEDURE Start*(t: Task; stackSize: LONGINT);
  BEGIN
    IF t.state # notStarted THEN TaskWaiting.Misuse(TaskWaiting.startOfStarted) END;
    Coroutines.Init(Trampoline, stackSize, t.coroutine);
    NEW(t.waiter); t.waiter.task := t;
    MakeReady(t)
  END Start;

  (* The running task; the main program's while it runs *)
  PROCEDURE Current*(): Task;
  BEGIN
    RETURN current
  END Current;

  (* Lets every other ready task run first *)
  PROCEDURE Yield*;
  BEGIN
    MakeReady(current);
    Block
  END Yield;

  (* Whether t's Run has returned *)
  PROCEDURE Done*(t: Task): BOOLEAN;
  BEGIN
    RETURN t.state = finished
  END Done;

  (* Waits until t's Run has returned; at once if it has *)
  PROCEDURE Join*(t: Task);
  BEGIN
    IF t = current THEN TaskWaiting.Misuse(TaskWaiting.joinOfRunning) END;
    IF t.state # finished THEN WaitIn(t.joiners); Block END
  END Join;

  (* Waits until c is signalled *)
  PROCEDURE Wait*(VAR c: Condition);
  BEGIN
    WaitIn(c.waiting);
    Block
  END Wait;

  (* Wakes the task that has waited on c longest, if any *)
  PROCEDURE Signal*(VAR c: Condition);
    VAR t: Task;
  BEGIN
    t := Remove(c.waiting);
    IF t # NIL THEN MakeReady(t) END
  END Signal;

  (* Wakes every task waiting on c *)
  PROCEDURE Broadcast*(VAR c: Condition);
    VAR t: Task;
  BEGIN
    t := Remove(c.waiting);
    WHILE t # NIL DO MakeReady(t); t := Remove(c.waiting) END
  END Broadcast;

  (* Takes m, waiting while another task holds it *)
  PROCEDURE Lock*(VAR m: Mutex);
  BEGIN
    IF m.holder = NIL THEN m.holder := current
    ELSE
      (* Unlock hands it over *)
      WaitIn(m.waiting);
      Block
    END
  END Lock;

  (* Gives m back, to the task that has waited longest, if any *)
  PROCEDURE Unlock*(VAR m: Mutex);
    VAR t: Task;
  BEGIN
    IF m.holder # current THEN TaskWaiting.Misuse(TaskWaiting.unlockNotHeld) END;
    t := Remove(m.waiting);
    m.holder := t;
    IF t # NIL THEN MakeReady(t) END
  END Unlock;

  (* Channels *)

  (* A channel that holds up to capacity messages; 0 makes each Send wait
     for a receiver *)
  PROCEDURE NewChannel*(capacity: LONGINT): Channel;
    VAR ch: Channel;
  BEGIN
    IF capacity < 0 THEN TaskWaiting.Misuse(TaskWaiting.negativeCapacity) END;
    NEW(ch);
    ch.capacity := capacity;
    IF capacity > 0 THEN NEW(ch.buffer, capacity) END;
    RETURN ch
  END NewChannel;

  PROCEDURE Enqueue(VAR q: WaiterQueue; w: Waiter);
  BEGIN
    w.next := NIL; w.previous := q.last; w.queued := TRUE;
    IF q.last = NIL THEN q.first := w ELSE q.last.next := w END;
    q.last := w
  END Enqueue;

  PROCEDURE Unlink(VAR q: WaiterQueue; w: Waiter);
  BEGIN
    IF w.previous = NIL THEN q.first := w.next ELSE w.previous.next := w.next END;
    IF w.next = NIL THEN q.last := w.previous ELSE w.next.previous := w.previous END;
    w.next := NIL; w.previous := NIL; w.queued := FALSE
  END Unlink;

  (* Takes the first waiter of q whose task is still waiting: a Select's
     other waiters stay queued until its task runs again *)
  PROCEDURE FirstWaiting(VAR q: WaiterQueue): Waiter;
    VAR w: Waiter;
  BEGIN
    w := q.first;
    WHILE (w # NIL) & (w.task.fired # NIL) DO Unlink(q, w); w := q.first END;
    IF w # NIL THEN Unlink(q, w) END;
    RETURN w
  END FirstWaiting;

  (* Wakes w's task, which then finds w in its fired *)
  PROCEDURE Fire(w: Waiter; delivered: BOOLEAN);
  BEGIN
    w.delivered := delivered;
    w.task.fired := w;
    MakeReady(w.task)
  END Fire;

  PROCEDURE Hold(ch: Channel; m: Message);
  BEGIN
    ch.buffer[(ch.head + ch.count) MOD ch.capacity] := m;
    INC(ch.count)
  END Hold;

  (* Hands m to a waiting receiver or holds it, if either can be done
     without waiting *)
  PROCEDURE Put(ch: Channel; m: Message): BOOLEAN;
    VAR w: Waiter;
  BEGIN
    w := FirstWaiting(ch.receivers);
    IF w # NIL THEN w.message := m; Fire(w, TRUE); RETURN TRUE
    ELSIF ch.count < ch.capacity THEN Hold(ch, m); RETURN TRUE
    ELSE RETURN FALSE
    END
  END Put;

  (* Takes a message held, or a waiting sender's, if there is one *)
  PROCEDURE Take(ch: Channel; VAR m: Message): BOOLEAN;
    VAR w: Waiter;
  BEGIN
    IF ch.count > 0 THEN
      m := ch.buffer[ch.head]; ch.buffer[ch.head] := NIL;
      ch.head := (ch.head + 1) MOD ch.capacity; DEC(ch.count);
      w := FirstWaiting(ch.senders);
      IF w # NIL THEN Hold(ch, w.message); w.message := NIL; Fire(w, TRUE) END;
      RETURN TRUE
    END;
    w := FirstWaiting(ch.senders);
    IF w # NIL THEN m := w.message; w.message := NIL; Fire(w, TRUE); RETURN TRUE END;
    RETURN FALSE
  END Take;

  (* Sends m on ch, if that can be done without waiting *)
  PROCEDURE TrySend*(ch: Channel; m: Message): BOOLEAN;
  BEGIN
    IF ch.closed THEN TaskWaiting.Misuse(TaskWaiting.sendOnClosed) END;
    RETURN Put(ch, m)
  END TrySend;

  (* Sends m on ch, waiting until a receiver takes it or ch has room *)
  PROCEDURE Send*(ch: Channel; m: Message);
    VAR w: Waiter;
  BEGIN
    IF ~TrySend(ch, m) THEN
      w := current.waiter;
      w.message := m; w.channel := ch;
      current.fired := NIL; current.state := blocked;
      Enqueue(ch.senders, w);
      Block;
      IF ~current.fired.delivered THEN
        w.message := NIL;
        TaskWaiting.Misuse(TaskWaiting.sendOnClosed)
      END
    END
  END Send;

  (* Receives a message from ch in m, if that can be done without
     waiting; m is NIL when it cannot *)
  PROCEDURE TryReceive*(ch: Channel; VAR m: Message): BOOLEAN;
  BEGIN
    m := NIL;
    RETURN Take(ch, m)
  END TryReceive;

  (* Receives a message from ch in m, waiting for one; FALSE, with m NIL,
     when ch is closed and holds no more *)
  PROCEDURE Receive*(ch: Channel; VAR m: Message): BOOLEAN;
    VAR w: Waiter;
  BEGIN
    IF Take(ch, m) THEN RETURN TRUE END;
    m := NIL;
    IF ch.closed THEN RETURN FALSE END;
    w := current.waiter;
    w.channel := ch; w.message := NIL;
    current.fired := NIL; current.state := blocked;
    Enqueue(ch.receivers, w);
    Block;
    m := w.message; w.message := NIL;
    RETURN w.delivered
  END Receive;

  (* Closes ch: no more can be sent. Its receivers waiting get FALSE, and
     its senders waiting trap (20). *)
  PROCEDURE Close*(ch: Channel);
    VAR w: Waiter;
  BEGIN
    IF ch.closed THEN TaskWaiting.Misuse(TaskWaiting.closeOfClosed) END;
    ch.closed := TRUE;
    w := FirstWaiting(ch.receivers);
    WHILE w # NIL DO w.message := NIL; Fire(w, FALSE); w := FirstWaiting(ch.receivers) END;
    w := FirstWaiting(ch.senders);
    WHILE w # NIL DO Fire(w, FALSE); w := FirstWaiting(ch.senders) END
  END Close;

  PROCEDURE SpareWaiter(): Waiter;
    VAR w: Waiter;
  BEGIN
    w := current.spares;
    IF w = NIL THEN NEW(w); w.task := current ELSE current.spares := w.sibling END;
    RETURN w
  END SpareWaiter;

  (* Receives a message in m from whichever channel of from has one first,
     waiting for one, and returns its index; the first in from's order when
     several have one. A NIL entry, or a channel closed and holding no
     more, is passed over; -1, with m NIL, when every entry is. *)
  PROCEDURE Select*(VAR from: ARRAY OF Channel; VAR m: Message): LONGINT;
    VAR i, index: LONGINT; open: BOOLEAN; w, waiters, next: Waiter;
  BEGIN
    LOOP
      open := FALSE;
      i := 0;
      WHILE i < LEN(from) DO
        IF from[i] # NIL THEN
          IF Take(from[i], m) THEN RETURN i END;
          IF ~from[i].closed THEN open := TRUE END
        END;
        INC(i)
      END;
      m := NIL;
      IF ~open THEN RETURN -1 END;
      current.fired := NIL; current.state := blocked;
      waiters := NIL;
      i := 0;
      WHILE i < LEN(from) DO
        IF (from[i] # NIL) & ~from[i].closed THEN
          w := SpareWaiter();
          w.index := i; w.channel := from[i]; w.message := NIL;
          Enqueue(from[i].receivers, w);
          w.sibling := waiters; waiters := w
        END;
        INC(i)
      END;
      Block;
      w := current.fired;
      index := -1;
      IF w.delivered THEN m := w.message; index := w.index END;
      w := waiters;
      WHILE w # NIL DO
        next := w.sibling;
        IF w.queued THEN Unlink(w.channel.receivers, w) END;
        w.message := NIL; w.channel := NIL;
        w.sibling := current.spares; current.spares := w;
        w := next
      END;
      IF index >= 0 THEN RETURN index END
      (* woken by a Close: look again *)
    END
  END Select;

BEGIN
  NEW(mainTask);
  mainTask.state := running;
  NEW(mainTask.waiter); mainTask.waiter.task := mainTask;
  current := mainTask
END Tasks.
