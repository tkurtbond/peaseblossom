# Tasks

A plan for option C of `doc/research/concurrency-survey.md`: a runtime
module `Tasks` of cooperative tasks, conditions, locks and channels,
written in Oberon over `Coroutines` (option B, `doc/developer/coroutines.md`),
with a way for asynchronous I/O, timers, signals and ASTs to wake a task.
Its phases follow on from `coroutines.md`'s, so they start at 7. The
decisions below were accepted by the user on 2026-11-14 and amended in
Phase 8 with Phase 7's probes, which `concurrency-survey.md` section 10
records; the survey's section 9 was the starting point.

There is still one thread and nothing preempts. A task runs until it
makes a call that can block (`Yield`, `Join`, `Sleep`, `Wait`, `Lock`,
`Send`, `Receive`, `Select`, `Await`, a wrapped read), and only then may
another run. Code between two such calls is atomic.

## What is there now

- **`Coroutines` on both back ends** (Phases 3-6), with `Init`,
  `Transfer`, `Free` and `DefaultStackSize`. `Transfer` already traps (17)
  in a finalizer, in a signal handler (LLVM) and at AST level (VAX, in a
  program that imports `AsynchronousTraps`). Every blocking call of
  `Tasks` that switches goes through `Transfer`, so it inherits those
  checks.
- **No way to wait for more than one thing.** `Platform.Delay` is
  `nanosleep` on Unix and a timer wait on VMS. Nothing in `rtl/llvm` calls
  `poll` or `select`. On VMS, `vmslib`'s `Timers` (`$SETIMR` with an AST),
  `EventFlags` and `AsynchronousTraps` exist; `Platform` uses `$QIOW`
  only to set the CTRL/C AST.
- **What a handler may do**: `language-extensions.md`, "Threads and
  signal handlers", and `vax-macro32-backend.md` section 22. A signal
  handler sets the program's own variables. An AST routine may also
  `NEW` in a program that imports `AsynchronousTraps`. Neither may
  `Transfer`.
- **pofltk** waits in FLTK's own loop (`Fl.Wait`, `Fl.AddFd`, timeouts),
  so a `Tasks` with its own loop would compete with it (survey 8.4,
  item 6).

## Interface (proposed)

Section 9.1's, with the answers below to 9.3's open questions:

```oberon
DEFINITION Tasks;

  CONST
    DefaultStackSize = Coroutines.DefaultStackSize;   (* 256 KiB, 32 KiB on the VAX *)

  TYPE
    Task = POINTER TO TaskDesc;
    TaskDesc = RECORD END;

  PROCEDURE (t: Task) Run;                 (* the body; returning ends the task *)
  PROCEDURE Start (t: Task; stackSize: LONGINT);
  PROCEDURE Current (): Task;              (* the main program is a task too *)
  PROCEDURE Yield;
  PROCEDURE Join (t: Task);
  PROCEDURE Done (t: Task): BOOLEAN;
  PROCEDURE Sleep (milliseconds: LONGINT);

  TYPE
    Condition = RECORD END;
    Mutex = RECORD END;

  PROCEDURE Wait (VAR c: Condition);
  PROCEDURE Signal (VAR c: Condition);
  PROCEDURE Broadcast (VAR c: Condition);
  PROCEDURE Lock (VAR m: Mutex);
  PROCEDURE Unlock (VAR m: Mutex);

  TYPE
    Message = POINTER TO MessageDesc;
    MessageDesc = RECORD END;
    Channel = POINTER TO ChannelDesc;
    ChannelDesc = RECORD END;

  PROCEDURE NewChannel (capacity: LONGINT): Channel;
  PROCEDURE Send (ch: Channel; m: Message);
  PROCEDURE Receive (ch: Channel; VAR m: Message): BOOLEAN;
  PROCEDURE TrySend (ch: Channel; m: Message): BOOLEAN;
  PROCEDURE TryReceive (ch: Channel; VAR m: Message): BOOLEAN;
  PROCEDURE Close (ch: Channel);
  PROCEDURE Select (VAR from: ARRAY OF Channel; VAR m: Message): LONGINT;
  PROCEDURE After (milliseconds: LONGINT): Channel;   (* decision 7 *)

  TYPE Event = RECORD END;

  PROCEDURE Await (VAR e: Event);
  PROCEDURE Post (VAR e: Event);           (* safe in a signal handler or an AST *)

  TYPE IdleStep = PROCEDURE (timeout: LONGINT);
  PROCEDURE SetIdleStep (step: IdleStep);  (* decision 10 *)

  (* POSIX only (decisions 10 and 11) *)
  PROCEDURE AwaitReadable (fd: LONGINT);
  PROCEDURE AwaitWritable (fd: LONGINT);
  PROCEDURE WakeDescriptor (): LONGINT;
END Tasks.
```

## Decisions

1. **`Tasks` is Oberon over `Coroutines`, the same source on both back
   ends.** What differs by system, the idle step and the traps, is in a
   small module of each runtime, `TaskWaiting`: C for `poll` and the
   self-pipe on LLVM, `["VMS"]` declarations on the VAX. A fixture checks
   that `rtl/llvm/Tasks.Mod` and `rtl/vax/Tasks.Mod` are the same file.
   No compiler change.

2. **A body is a type-bound `Run` of an extension of `TaskDesc`** (9.2).
   `Start` gives the task a coroutine whose body is `Tasks`' own
   trampoline, which calls `Current().Run`. **Returning ends the task**,
   and it is not trap 16. The trampoline marks the task done, wakes its
   joiners, and switches away for good. Its stack is freed by the next
   task to run, since `Coroutines.Free` of the running coroutine traps:
   `Tasks` keeps one "stack to free" variable and checks it after every
   switch.

3. **No scheduler coroutine.** A task that blocks takes the next ready
   task from a FIFO run queue and transfers straight to it, so a switch
   costs one `Transfer`, not two. When no task is ready, the blocking
   task runs the idle step on its own stack (decision 9). `Yield` puts
   the running task at the queue's end. `Signal` wakes the longest
   waiter. Conditions are Mesa's: a woken task tests again
   (`WHILE ~ok DO Wait(c) END`). Phase 7.2 measured it against a
   scheduler coroutine every switch goes through: that costs 2.6-3.5
   times as much per `Yield` on x86 and 1.3-1.5 times on the VAX (survey
   10.2), so direct switching stays.

4. **The program ends when the main module's body ends**, as in Go (9.3,
   1). Tasks still running are abandoned: their finalizers run, as
   at any end, but their `Run`s do not finish. `Join` is how to wait.
   Ada's master rule would need a hook in the program's end on both back
   ends, and Oakwood's style has no masters.

5. **Deadlock traps (19), "all tasks are blocked"** (9.3, 2), as Go's
   "all goroutines are asleep" does. That is when no task is ready, no
   timer is pending, no task waits for I/O, and no task is in `Await`.
   A task in `Await` can be woken by a handler, so it is never a
   deadlock. On the VAX the status is `%X1000009A`.

6. **Misuse traps (20), with a text for each case, as 17 has**: `Unlock`
   of a mutex the running task does not hold, `Join` of the running task,
   `Send` on a closed channel, `Close` of one already closed, a `Start`
   of a task already started, a negative capacity. A blocking call in a
   finalizer, a signal handler or an AST traps already, as 17, through
   `Transfer`; one that would not block there returns normally, and the
   guide says not to rely on it. On the VAX, `PocRtl.mar`'s text table
   grows again, and its slots move as in Phase 4.

7. **Messages are extensible records** (9.1, 9.3 item 3). `NIL` is a
   message too. Typed channels for the basic types are left for later.
   **`Select` receives only, and a timeout is a channel**: `After(ms)`
   returns a channel that gets one message after `ms` milliseconds, as
   Go's `time.After`, so `Select` needs no timeout of its own (9.3, 4).

8. **No cancellation at first** (9.3, 5). A program can close a channel
   its tasks watch. **Mixing with `Coroutines`** (9.3, 6): a program that
   imports `Tasks` may use `Coroutines` only inside one task, between
   coroutines `Tasks` does not own, and must be back on that task's own
   coroutine before it calls `Tasks` again. Nothing checks it, because
   `Coroutines` cannot say which coroutine is running without a new
   export.

9. **`Event` is the bridge, and `Post` only sets flags.**
   - `Post` sets the event's flag and a global "something was posted"
     flag. It never touches a queue and never allocates, so a signal
     handler or an AST may call it ("Threads and signal handlers").
   - The scheduler looks at the waiting tasks' events only when the
     global flag is set, so a program that never posts pays one test per
     switch.
   - **The early poll.** The idle step runs only when no task is ready,
     so a task that only yields would keep a task waiting for a ready
     descriptor waiting until it stops (500 of 500 ms in Phase 7.3). So
     while tasks are ready and some task waits for a descriptor, `Tasks`
     counts the tasks it picks, and at every 256th reads the clock and,
     if 1 ms has passed since the last poll, polls without waiting. A
     ready descriptor then waits about 1 ms and 256 picks at most; a
     pick costs a few ns more, and nothing when no task waits for a
     descriptor (survey 10.3). On VMS a completion AST posts an event,
     and events need no such rule: the scheduler harvests them on every
     pick.
   - **The idle step, POSIX**: `poll` on the descriptors tasks wait for,
     plus the read end of a self-pipe, with the nearest timer as its
     timeout. `Tasks` sets an "idle" flag before it last looks at the
     posted flag. `Post` writes one byte to the self-pipe when that flag
     is set; `write` is async-signal-safe. So a signal that comes between
     the look and `poll` still wakes it. `ppoll` would do the same, but
     NetBSD 9 and older lack it.
   - **The idle step, VMS**: `$HIBER`, with a `$SETIMR` for the nearest
     timer whose AST wakes. `Post` at AST level calls `$WAKE`, which VMS
     remembers if the process is not hibernating yet, so no wake is
     lost; an AST that did not wake leaves the process hibernating
     (survey 10.1). `$SETIMR` carries `Tasks`' own request identifier,
     so `$CANTIM` cancels its timer alone; `Tasks` never calls `$SCHDWK`
     or `$CANWAK`, since `$CANWAK` cancels every scheduled wakeup in the
     process, other code's too. A `$HIBER` that returns for no reason of
     `Tasks`' own is accepted: it looks again and loops. An I/O wait is a
     `$QIO` whose completion AST posts an event.
   - **`Sleep` and `After` wait at least their time.** On OpenBSD and
     NetBSD `poll` rounds its timeout up to the 10 ms clock tick, so a
     `Sleep` there ends up to two ticks late (survey 10.3); the VAX's
     clock ticks every 10 ms too.
   - Phase 7.3 lost no wake: 10000 posts on each of five Unix hosts,
     700 a run on the VAX guest, a signal or an AST at random moments.

10. **The idle step can be replaced** (8.4, item 6). `SetIdleStep(p)`
    has `Tasks` call `p(timeout)` instead of its own wait; `-1` means
    "no limit". After `p` returns, `Tasks` polls without waiting, which
    finds ready descriptors and empties the self-pipe. pofltk's is
    `Fl.Wait(timeout / 1000)`, and FLTK callbacks `Post` the events tasks
    wait for. pofltk is Unix only, so this is a hook, not a dependency.
    Phase 7.4 ran it (survey 10.4) and showed three rules the guide
    gives, since `Tasks` cannot check them:
    - **A replaced step must return when a handler posts.** On POSIX
      `Tasks` exports `WakeDescriptor()`, the self-pipe's read end, and
      the step must return when it is readable: pofltk's watches it
      with `Fl.WatchFd` and an action that does nothing. Without that, a
      signal that comes between `Tasks` marking itself idle and FLTK
      entering `select` waited for FLTK's next event (one in 1000, 999
      ms), and a post from an FLTK timer's action waited for the next
      timer (9 ms on average, against 0.1 ms watched).
    - **A replaced step must watch the descriptors tasks wait for**, or
      a task in `AwaitReadable` waits for the step's next event. The
      simplest way is the toolkit's own watch, whose action posts an
      `Event` the task awaits.
    - **A replaced step runs on the stack of whichever task idles**, so
      every task needs room for the toolkit's event handling: FLTK and
      Xlib crashed on 32 KiB stacks and ran on 40 KiB, and
      `DefaultStackSize` is the guide's advice. Running the step on the
      main program's stack instead would cost two switches per idle
      step.

11. **I/O wrappers are separate modules.** `Tasks` exports no I/O.
    - **`TaskInput`**, on both back ends: `Line(VAR s)` and `Char(VAR
      c)` from the standard input, waiting as a task. On POSIX it waits
      for the descriptor to be readable, then reads. On VMS it reads
      `SYS$INPUT` with a `$QIO` and an AST.
    - On POSIX, `Tasks` also exports `AwaitReadable(fd)` and
      `AwaitWritable(fd)` through `TaskWaiting`, for pipes, terminals
      and sockets. A regular file is always "ready", so a disk read
      still blocks every task (survey 9.2).
    - On VMS, a program's own `$QIO` with an AST that calls `Post` is
      the general way, and the VAX/VMS Guide shows it.
    - `TaskFiles` (wrapped `Files`) is not in this plan: on POSIX a
      regular file is always "ready", so a wrapper could not keep a disk
      read from blocking. It is left for later on the VAX, where a disk
      `$QIO` is asynchronous ("Later").
    - Sockets are not in this plan either ("Later").

12. **Stacks.** `DefaultStackSize` is `Coroutines.DefaultStackSize`, not
    9.1's 64 KiB, so that the two modules agree. A task that is never
    joined and blocks for good keeps its stack until the program ends,
    as a coroutine never freed does. A task blocked on a channel nothing
    else can reach is a leak, as in Go, and the guide says so.

13. **On VMS, `Tasks` switches without `Coroutines`' AST-level check.**
    In a program that imports `AsynchronousTraps` (STARLET does, and so
    does most of VMSLIB), `Coroutines.Transfer` calls `LIB$AST_IN_PROG`
    and `$SETAST` twice, which made a `Yield` pair 30 µs instead of 7.5
    on the guest (survey 10.3). Measured alone, `LIB$AST_IN_PROG` is
    8.6-16.4 µs a call and the `$SETAST` pair 2.0-2.6 µs (Phase 8,
    2026-11-14), so the check is most of it, and the pair, which keeps
    an AST's collection from scanning the wrong stacks, is not optional.
    `Coroutines` gets one export for `Tasks`, a `Transfer` without the
    AST-level check, as `GarbageCollectedHeap` has exports for
    `Coroutines` that are undefined otherwise; `Transfer` itself is
    unchanged. A blocking call of `Tasks` in an AST routine is then
    undefined, not trap 17, and the guide says so, as it already says a
    blocking call in a signal handler is wrong. The finalizer check
    stays: it is one test. On LLVM nothing changes, since the signal
    handler check is one test too.

14. **What else the guide says** (survey 10.1, 10.2):
    - An override of `Run` must be exported (`PROCEDURE (t: T) Run*`),
      since the base procedure is.
    - On VMS, run a `Tasks` program under the debugger only with
      `DEFINE DBG$PROCESS NONE`: the default two-process debugger loses
      a remembered `$WAKE`, and the program can hang.

## What changes

| File | Change |
|---|---|
| `rtl/llvm/Tasks.Mod`, `rtl/vax/Tasks.Mod` (new, the same file) | Tasks, the run queue, conditions, mutexes, channels, `Select`, timers, events, deadlock detection |
| `rtl/llvm/TaskWaiting.Mod` and `.c` (new) | `poll`, the self-pipe, the clock, `AwaitReadable`/`AwaitWritable`'s descriptor list, traps 19 and 20 |
| `rtl/vax/TaskWaiting.Mod` (new) | `$HIBER`, `$WAKE`, `$SETIMR`, `$CANTIM`, the clock, traps 19 and 20 through `POC_TRAP` |
| `rtl/llvm/Coroutines.Mod`, `rtl/vax/Coroutines.Mod` | The `Transfer` without the AST-level check, for `Tasks` (decision 13); on LLVM the same as `Transfer` |
| `rtl/llvm/TaskInput.Mod`, `rtl/vax/TaskInput.Mod` (new) | Standard input read as a task |
| `rtl/vax/PocRtl.mar` | Texts for 19 and 20, with 20's cases by high word |
| `GNUmakefile`, the kits | The new modules carried and built |
| `packaging/` | The PLISTs list the new modules' files |
| `doc/developer/language-extensions.md`, `AGENTS.md` | Trap rows 19 and 20. A section "Tasks" after "Coroutines" |
| `rtl/llvm/README.md`, `rtl/vax/README.md`, `doc/reference-guide.md` | The modules' entries; `tools/rtl-reference update` |
| `doc/users-guide.md`, `doc/examples/` | A chapter on tasks, with Phase 12's examples |
| `doc/vax-vms-guide.md` | Tasks on VMS: `$HIBER`, an AST that posts, `$QIO` |
| `doc/research/concurrency-survey.md`, `PLAN.md` | Section 6 and Phase 19's candidate 7 record C as adopted |

## Plan

As for B: each phase is checked on atla, cymoril, artos and alerik before
it is committed, the VAX phases run their fixtures on the guest, and each
phase is shown to the user and committed only when the user asks. rackhir
runs after Phases 9 and 10 and at the end. The work is done on a branch,
`tasks`, made from `coroutines` or from `main` once B is merged.

### Phase 7: Probes

Before the decisions are final. Nothing is committed but the survey's
record of the results, as a section 10.

#### Phase 7.1: The manual

Check `$HIBER`, `$WAKE`'s remembered wake, `$SCHDWK`, `$CANWAK`, and
`$QIO`'s AST on a terminal read, against the VMS 5.5 *System Services
Reference Manual* (`AA-LA69B`, fetched 2026-10-05; this plan said
otherwise until Phase 8). Done: survey 10.1.

#### Phase 7.2: A prototype

A scratch `Tasks` with decisions 2, 3 and 9, and channels, built against
`Coroutines` on atla, cymoril, artos, alerik and the guest. Measure a
channel round trip (ping-pong between two tasks), `Yield`, and `Start` +
`Join`, against 8.2's `Transfer`. The figures decide whether decision 3's
direct switching is worth its "stack to free" variable.

#### Phase 7.3: Waking

- POSIX: a ticker task, a task in `AwaitReadable` on a pipe written
  slowly by a child process, and a SIGINT handler that posts, with the
  signal sent at random moments, many times, to show that no wake is
  lost. On every Unix host, and on rackhir.
- VMS: the same with `$SCHDWK`, a `$QIO` read of a mailbox written by a
  subprocess, and an AST from `Timers.After` that posts.

#### Phase 7.4: pofltk

`SetIdleStep` with `Fl.Wait`: a ticker task updating a label while the
window stays live, and a button's callback that posts.

### Phase 8: The decisions

Write the decisions, with Phase 7's results, into `language-extensions.md`
(trap rows 19 and 20, a section "Tasks" after "Coroutines") and
`AGENTS.md`'s summary, and give the plan an entry in `PLAN.md`'s "Ongoing
library enhancements". Done 2026-11-14: decisions 3, 9 and 10
amended, 13 and 14 added, the interface given `WakeDescriptor`,
`AwaitReadable` and `AwaitWritable`.

### Phase 9: The core

`Tasks.Mod` without time or events (`Sleep`, `After`, `Event` and the
idle step come in Phase 10): tasks, `Yield`, `Join`, `Done`, conditions,
mutexes, channels, `Select`, deadlock, misuse. The same file in both
runtimes, with `TaskWaiting`'s traps. Fixtures, each comparing its
output, each with its `.gitignore` line, on LLVM and, as `vax-tasks-*`,
on the guest:
- `llvm-tasks`: start, run, join, the run queue's order, `Yield`, a
  task's stack freed after it returns (many short tasks, memory flat);
- `llvm-tasks-channels`: buffered and unbuffered, `Close`, `Receive`'s
  FALSE, `TrySend`/`TryReceive`, `Select`, Go's concurrent prime sieve;
- `llvm-tasks-sync`: conditions (Mesa), `Broadcast`, a mutex held across
  a `Send`;
- `llvm-tasks-traps`: deadlock (19), each case of 20, a blocking call in
  a finalizer (17);
- `llvm-tasks-collector`: messages held only in channels and on blocked
  tasks' stacks survive many collections;
- `tasks-same-source`: the two `Tasks.Mod` are the same.

### Phase 10: Time and events

`Sleep`, `After`, `Event`, `Await`, `Post`, `SetIdleStep`, the idle step
on POSIX and VMS, and `AwaitReadable`/`AwaitWritable` on POSIX. Fixtures:
- `llvm-tasks-time`: sleeps of several lengths end in order, `After` in a
  `Select`;
- `llvm-tasks-events`: Phase 7.3's POSIX probe, made to compare output;
- `llvm-tasks-idle`: a replaced idle step called with the right timeout;
- `vax-tasks-time`, `vax-tasks-events`: the same on the guest, with an AST
  from `Timers.After` and a mailbox `$QIO`.

### Phase 11: Standard input

`TaskInput` on both back ends. Two questions from Phase 7.1 (survey 10.1)
are settled here: on a VMS terminal, output queues behind a pending read
once the user starts typing, so a ticker task's output stops the whole
process until the line ends; and a `SYS$INPUT` that is a disk file is
not read by a record `$QIO`, so `TaskInput` on VMS needs a synchronous
RMS fallback when it is neither a terminal nor a mailbox. Fixtures: on Unix, lines fed through a
pipe slowly while a ticker task runs, its ticks interleaved with them;
on the guest, the same from a file and from a mailbox.

### Phase 12: Examples

Two programs in `doc/examples/tasks/`, in a User's Guide chapter around
them, checked by `tools/guide-examples`, and run on the guest by
`vax-tasks-examples` both ways (MACRO-32 and objects):
- **Primes**: Go's concurrent prime sieve, a chain of filter tasks joined
  by channels;
- **Clock**: a ticker task and a task reading commands from standard
  input, with `Select` over the ticks, the commands, and an `After`
  timeout.

A pofltk example, from Phase 7.4, goes into pofltk's own repository,
not poc's.

### Phase 13: Documents and packaging

`rtl/llvm/README.md`, `rtl/vax/README.md`, `tools/rtl-reference update`,
the VAX/VMS Guide's "Tasks", the PLISTs, `PLAN.md`'s entry marked
`[done]`, and the survey and Phase 19's candidate 7 recording C as
adopted.

## Later

Possibilities recorded with the user (2026-11-14), not part of this plan:

- **`TaskFiles` on the VAX**: `Files`' reads and writes over `$QIO`,
  with its buffers and riders kept, so a disk wait lets other tasks run.
  VMS only; on POSIX it could not help (decision 11).
- **Sockets**: a `Sockets` module, useful without `Tasks`, whose calls
  that can block have forms a task waits in. On POSIX, a non-blocking
  socket and `AwaitReadable`/`AwaitWritable` are enough, with no change to
  `Tasks`. On VMS the TCP/IP stack is not one thing: the SIMH guest runs
  UCX, but a VAX the user runs poc on has MultiNet, probably not a recent
  one, so a VMS `Sockets` would need both stacks' interfaces probed.
- **A Gemini server, Unix only**, over `Sockets`, `Tasks` and a TLS
  layer, the program that motivates both. Gemini requires TLS, and no
  TLS library is known for VMS 5.5-2. On Unix, libtls (LibreSSL's, or
  libretls over OpenSSL) is the binding to try first: its `tls_read` and
  `tls_write` say `TLS_WANT_POLLIN` or `TLS_WANT_POLLOUT`, which map onto
  `AwaitReadable` and `AwaitWritable`. Until then, a poc program can serve
  Gemini under inetd behind a TLS proxy (stunnel, or relayd on OpenBSD),
  reading the request with `In` and writing the response with `Out`.

**Size [inferred]:** about 800 lines of Oberon for `Tasks`, 150 of C and
150 of Oberon for the two `TaskWaiting`s, 150 for the two `TaskInput`s,
and some 15 fixtures.
