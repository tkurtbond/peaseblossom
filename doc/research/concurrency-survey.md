# Concurrency: what the Oberons, Modula-2, Modula-3, Ada and Go do, and what poc should do

Written 2026-11-13 at the user's request: a survey of concurrency in
the Oberon languages, Modula-2, Modula-3, Ada and Go, and a
recommendation on whether and how Peaseblossom should add
concurrency, or leave it out. `Oberon2.pdf` says nothing on the
subject, so there is no rule poc falls short of; this is a Phase 19
style survey ("each candidate gets a survey, then the user's
decision; not adopted is a legitimate result").

The survey says what each source *does* and marks what could not be
verified. Section 4 probes what poc does today, on the LLVM back end
and with DECthreads on the SIMH VAX. Section 6 gives the options and
a proposal. Section 9 sketches one possible interface for option C.
**Nothing here changes poc.**

"[inferred]" marks a conclusion of this survey, not something a source
says.

## 1. The questions

1. Should poc have concurrency at all? If it should, how much, and at
   which level: language, library, or neither?
2. Which model fits **both** back ends? The LLVM back end runs on Linux
   and the four BSDs, 32- and 64-bit, x86 and arm64. The VAX back end
   runs on VAX/VMS 5.5-2, which has no kernel threads.
3. What does each model cost poc's runtime? Above all, what does it
   cost the collector, which today scans one stack conservatively and
   whose heap has no lock?
4. Which rule for shared variables would poc promise?
5. What does a program that does not use concurrency pay? (The project
   rule is that it should pay nothing.)

## 2. What the language definitions say

### 2.1 The Oberon family

| Source (local file) | Says |
|---|---|
| `Oberon2.pdf`, `Oberon2-Report.pdf`, `Oberon.Report.pdf` | Nothing. There are no processes, coroutines, monitors or signals, and nothing in `SYSTEM`. |
| `From-Modula-to-Oberon-eth-3205-01.pdf` (p. 7) | Modula-2's coroutines (`NEWPROCESS`, `TRANSFER`, `IOTRANSFER`) and module priorities were **removed on purpose**. Oberon is single-process, and multiprogramming is left to the system. |
| `Project-Oberon/PO.System.pdf` (2013; pp. 17, 28) | The Oberon system has one process. "Tasks" are background procedures that the central loop calls between commands, so they are **cooperative** and each runs to completion. The collector runs between commands, when the stack is empty, so no locks are needed. In the 1992 edition (`ProjectOberon1992.pdf`) `Oberon.Task` has a `safe` flag. In 2013 `NewTask` takes a period. |
| `Oberon-2012/Interrupts.pdf` | Oberon-07 on RISC5 has interrupt procedures, `PROCEDURE P [4]`, and nothing more. |
| `oakwood-guidelines.pdf` §1.2.8 (p. 42) | An **optional `Coroutines` module**, proposed by Mössenböck: `Init(body: PROCEDURE; stackSize: LONGINT; VAR cor: Coroutine)` and `Transfer(VAR from, to: Coroutine)`. `body` must not return. |
| `oakwood-guidelines.pdf` §3.4 (p. 15) | Interrupt procedures: target-dependent, not portable. |
| `Active-OberonLanguageReport.pdf` (2019) | An object's body may be `ACTIVE`, "in which case the body of the object is executed on a separate thread". Its statement blocks may be `EXCLUSIVE`, which locks the object as a monitor does, and `AWAIT(cond)` waits for a condition: a conditional critical region. It also has `PRIORITY` and a `CAS` builtin. Its "Active Cells" subset adds CSP-like `PORT IN/OUT` with blocking and non-blocking send and receive. |

### 2.2 Modula-2 and Modula-3

| Source (local file) | Says |
|---|---|
| `Richardson1980_Chapter_ACritiqueOfModula.pdf` | Modula (1977) had processes, interface modules (monitors) and signals. Richardson criticizes them as too rigid for general use. |
| `Modula-2/pim2-4e-bok_978-3-642-83565-0.pdf` (PIM 4th ed.) | `SYSTEM.NEWPROCESS`, `TRANSFER` and `IOTRANSFER` provide coroutines. A module may have a priority, which masks interrupts. The `Processes` library (ch. 30) builds processes and signals on top of them. The rationale is on p. 133: Modula's processes were "replaced by the lower-level notion of coroutines", so that a library can build any scheduling policy. |
| `Modula-2/ISO-IEC-10514-1-...pdf` | ISO Modula-2 has the `COROUTINES` module: `NEWCOROUTINE`, `TRANSFER`, `IOTRANSFER`, `ATTACH`, `LISTEN` and `PROT` (protection levels). The modules `Processes` and `Semaphores` are optional. |
| `Modula-3/Modula-3_Language_Definition.pdf` | `MUTEX` is a predeclared object type (`MUTEX <: ROOT`). `LOCK mu DO S END` means acquire, then `TRY S FINALLY` release. A **required** `Thread` interface gives `Fork(Closure)`, `Join`, `Wait`, `Signal`, `Broadcast` and `Alert`. The rationale (§1.4.4) calls Modula-2's coroutines too weak for real multiprocessing, and calls threads "a tool with a very sharp edge". The definition states **no rule for data races**. Birrell's SRC report 35, "An Introduction to Programming with Threads", is the companion text. |

### 2.3 Ada

| Source (local) | Says |
|---|---|
| Ada 83 LRM ch. 9 (`Languages/Ada/ARM/83/lrm-text/lrm-09`) | Tasks and task types. "Each task can be considered to be executed by a logical processor of its own", and the Note allows "interleaved execution on a single physical processor". A master is not left until its dependent tasks have terminated (9.4). Tasks communicate by **rendezvous**: `entry`/`accept`, where the caller names the acceptor but not the reverse. The selective wait `select` has guards, `terminate`, `delay` and `else` (9.7). `pragma PRIORITY` (9.8). `abort` (9.10). **Shared variables (9.11):** between synchronization points, conflicting access is *erroneous*. `pragma SHARED` makes each access a synchronization point. |
| Ada 83 Rationale ch. 13 (`Rationales/83/ratl-13-0{1,3}.html`) | It rejects semaphores ("too low a level") and monitors ("an unfortunate mix of high-level and low-level concepts"). It rejects channels, to avoid "an additional language concept". It rejects CSP's symmetric naming because then "it is not possible to program a library routine to provide resources to arbitrary users". "It is much more difficult to program a rendezvous in terms of non-rendezvous primitives than vice versa." |
| Ada 95 Rationale part 2 ch. 9 (`ARM/95/rat95html/rat95-p2-9.html`) | **Protected objects**: functions run under a read lock, procedures under the write lock, and entries have barriers. The reason given: the rendezvous "had not proved adequate for problems of shared data access" and had "a relatively high overhead". A protected object is "a very efficient conditional critical region", "an amalgam of the best features of conditional critical regions and monitors". The **proxy model**: the task that changes the state runs the waiting callers' entry bodies, which gives "no extra context switches". In the buffer example this is three times better in context switches than semaphores, and twice as good in locks. Ada 95 also added `requeue` and asynchronous transfer of control (ATC). |
| Ada 2022 AARM (`ARM/2022/AA-22-Txt.zip`) 9.5, 9.10, 9.10.1, 5.5, 5.6.1, D.13 | 9.5.1: a potentially blocking operation inside a protected action is a bounded error. 9.10 defines "signals", "sequential", "concurrent" and "conflict", and says "two concurrent actions [with] conflicting uses of a shared variable" are erroneous. The `parallel` block and `parallel` loop (5.5, 5.6.1) are logical threads, which an implementation may merge. **Conflict checks are on by default for parallel constructs**, but not between tasks (9.10.1). Ravenscar and Jorvik are in D.13. |
| *Overview of Ada 2022* (Jeff Cousins, version 121, 8 January 2025; `Rationales/2022-no-rationale-bug-an-overview-instead/Ada2022-Overview.pdf`, also www.ada-auth.org/standards/overview22.html). Ada 2022 has no Rationale; this Overview takes its place. | **Ch. 1:** the first of WG 9's instructions to the ARG was "Improving the capabilities of Ada on multi-core and multi-threaded architectures". Ada's tasking had made the first multi-core processors "relatively easy", but "latent timing problems would emerge when tasks were truly running on different processors instead of just pretending to". **Ch. 2:** the parallel constructs are meant to "use lightweight threading so as to incur less overhead than tasking". OpenMP is named as the likely platform. "To reduce implementation complexity and reduce the risk of deadlock, blocking is not allowed in a parallel construct": calling a potentially blocking operation there is a bounded error. Conflicting activities are "considered erroneous". "It is important that the default for the new parallel constructs is that all possible conflicts are checked, but for backward compatibility we want the default for tasking constructs to be no checks." The checks rest on the `Nonblocking` aspect (§2.3) and the `Global` annotations taken from SPARK (AI12-0079-3); generalizing those to all of Ada "has been far from trivial". It warns that the parallel features "may be the last ones to be implemented". **§6.10:** Jorvik "is less restrictive than the Ravenscar profile... but still allows timing and storage analyses". It drops `No_Implicit_Heap_Allocations`, `No_Relative_Delay`, `Max_Protected_Entries => 1` and the bans on `Ada.Calendar` and `Ada.Synchronous_Barriers`, and it replaces `Simple_Barriers` with `Pure_Barriers` (side-effect-free Boolean expressions, `'Count` allowed). |
| `ravenscar-guide-n424.pdf` | Ravenscar is a fixed set of library-level tasks without entries, plus protected objects with at most one entry, a simple barrier and one queued caller. There is no `select`, `abort`, `requeue`, task hierarchy or dynamic priority. The aims are "determinism, schedulability analysis and memory-boundedness", and "a small and efficient run-time system... certifiable to the highest integrity levels". |

### 2.4 Go

| Source (web, fetched by the survey) | Says |
|---|---|
| The Go spec (go.dev/ref/spec, go1.27) | `go f(x)` starts "an independent concurrent thread of control, or goroutine, within the same address space". Channels are typed and directional, optionally buffered, and can be closed. `select` chooses "via a uniform pseudo-random selection" among the cases that can proceed. |
| The Go memory model (go.dev/ref/mem, 2022) | **DRF-SC**: a program without data races behaves "as if all the goroutines were multiplexed onto a single processor". A race on a **multiword** value (an interface, slice, string or map) "can lead to arbitrary memory corruption". The happens-before edges come from channel operations, `sync`, `sync/atomic` (sequentially consistent) and `SetFinalizer`. "If you must read the rest of this document to understand the behavior of your program, you are being too clever." |
| FAQ, Effective Go | "Do not communicate by sharing memory; instead, share memory by communicating." Concurrency was built on CSP because pthreads put too much weight on "mutexes, condition variables, and memory barriers". Maps are not locked, because "requiring that all map operations grab a mutex would slow down most programs and add safety to few". "Automatic garbage collection makes concurrent code far easier to write." |

### 2.5 The ancestors

- **CSP** (Hoare, CACM 1978): `P!e` sends and `Q?x` receives, by synchronous handoff. `[P1 || P2]` runs processes in parallel, and guarded commands may have input guards. Processes share no variables.
- **occam** uses named channels with `SEQ`, `PAR` and `ALT`. The compiler checks that no two `PAR` branches write the same variable.
- **Concurrent Pascal** (Brinch Hansen, 1975) introduced monitors. Its compiler checked that processes interact only through monitors. In "Java's insecure parallelism" (SIGPLAN Notices 34(4), 1999), Brinch Hansen argues against notations that make "time-dependent errors" the default case.

These were cited from memory or secondary text and were **not
verified** against the originals, except Brinch Hansen 1999, which was
read.

## 3. What the implementations do

### 3.1 Oberon compilers

- **voc, ofront, OBNC, obc**: no concurrency. voc's `Heap.Mod` scans one stack, and voc's library has no coroutine module (checked in `src/library`).
- **oo2c**: a `PThread` module over POSIX threads. It depends on the Boehm collector built with thread support, and `liboo2c.Mod` (lines 4-12) warns that the library itself is not thread-safe.
- **Linz Oberon V4** (`Threads.Mod`, Lichtenberger): it opens `libpthread` with `dlopen`. To collect, it stops the other threads with signal 31 and scans their stacks conservatively. Modules that may be called from several threads register with `RegisterReentrant`.
- **ETH System 3**: `Coroutines.Mod`, the Oakwood interface. It is still shipped as an Oberon+ demo.
- **BlackBox / Component Pascal**: `Services.Action` and `DoLater`, which are cooperative and run from the event loop, like Project Oberon's tasks.
- **A2 / Active Oberon on Unix**:
  - Each active object runs on its own pthread.
  - To collect, the collector suspends every thread (SIGUSR2/SIGUSR1) and scans each one's saved `ucontext` and stack. Insertion write barriers are optional (`--writeBarriers`).
  - The heap has one lock. **Finalizers run in a process of their own**, to avoid deadlocks.
  - `AWAIT` compiles to a call of a condition procedure, with an inline pre-test that avoids 70-85 % of the calls (Muller's thesis, `eth-26082-02.pdf` §5.11.1). The process that leaves an `EXCLUSIVE` region evaluates the waiters' conditions and hands the lock over.
- **A2 native**: the collector stops the world at a tick barrier. Real-time (`PRIORITY`) activities may not allocate. The "Coop" variant inserts preemption checks on loop back edges.
- **Zonnon** (on .NET): activities and protocols. Read on the web only, not verified.

### 3.2 Modula-2 and Modula-3 compilers

- **Lilith** (`ETH_Lilith_1984.pdf`, `Lilith_Manual_1982.pdf`): `TRANSFER` is a microcoded instruction. The heap allocator may be called only from the main coroutine.
- **GNU Modula-2** (`gm2-15.pdf`; checked by the survey with a test program): each coroutine is a **pthread**. They pass a baton under one global lock, so only one runs at a time. The workspace given to `NEWCOROUTINE` is ignored.
- **CM3 (Modula-3)** has two thread packages:
  - `ThreadPThread` uses OS threads. `StopWorld` sends `pthread_kill` with a suspend signal, and each thread's `ucontext` is captured. A thread inside the heap's critical section (`heapState.inCritical`) is allowed to leave it before being stopped.
  - `ThreadPosix` provides user threads, time-sliced by `SIGVTALRM`, using `ucontext`. It **does not build on OpenBSD**.
  - Collection uses Bartlett's mostly-copying collector, which pins every page a stack word points to, so stacks can be scanned conservatively. The compiler now emits the barriers.

### 3.3 Ada implementations

- **GNAT 16** (`/usr/lib/gcc/x86_64-redhat-linux/16/adainclude`, `s-taprop.adb`):
  - One `pthread_create` per task, with about 2 MB of stack, seen with strace.
  - A protected object is a `pthread_mutex`, or a `pthread_rwlock` under locking policy `R`.
  - `abort` is done with a signal. Ceiling locking is silently ignored without privilege.
  - **Proxy model confirmed by experiment**: a protected entry's body ran on the producer's thread, not on the consumer's.
  - GNAT has no collector, so no task stack is ever scanned.
- **DEC Ada 3.2 on VAX/VMS 5.4 and later** (`~/Reference/Computer/OS/VMS/Ada/ada_rtr.pdf`, AA-PWGZB-TK, February 1995; a VMS 5.4+ manual, so it applies to 5.5-2):
  - §7.1: "all tasks in any Ada program (including the main task) currently run in the context of a single process... This switch can occur midway through the execution of an Ada source line."
  - §7.2.2: the main task's stack is in P1 and grows. Every other task gets a **fixed** P0 stack: 60 pages by default on VAX, plus 10 guard pages and 21 pages for non-Ada calls. Touching a guard page gives `SS$_ACCVIO`.
  - §7.3: scheduling is FIFO with preemption, priorities 0..15. `pragma TIME_SLICE` gives round robin, in steps of 0.01 s.
  - §7.4.9: most of the C RTL is not reentrant, and the FORTRAN RTL is only AST-reentrant. `LIB$`, `MTH$`, `OTS$` and `STR$` are fully reentrant.
  - §7.5.1: a task in a VMS wait state blocks the whole process. `TASKING_SERVICES` uses the asynchronous service forms instead (`SYS$QIO`, not `SYS$QIOW`) and suspends only the calling task until an AST reports completion.
  - §7.5.2: "the DEC Ada tasking implementation relies heavily on the use of ASTs... disabling ASTs with SYS$SETAST can cause deadlocks."
  - §7.7.1: `pragma AST_ENTRY` lets an AST routine queue an entry call without waiting for the rendezvous.
  - §1.4.2: "DEC Ada does not provide garbage collection."

  The survey did not verify whether DEC Ada used DECthreads on Alpha.

### 3.4 Go's runtime

The Go documents were read in full:
- the FAQ and the 1.4, 1.5 and 1.14 release notes;
- "Contiguous stacks";
- Vyukov's "Scalable Go Scheduler Design Doc" (2012);
- proposal 24543 on non-cooperative preemption;
- Hudson's "Go 1.4+ GC Plan" (2014).

The pacer document was not read.

- **Goroutines** are multiplexed **M:N** onto OS threads. G is a goroutine, M an OS thread, and P a processor slot; there are `GOMAXPROCS` P's. An idle P steals half of another P's run queue. When an M enters a system call, the runtime makes sure another M runs Go code.
- **Stacks start at 2 KB and are moved when they grow.** Each function's prologue checks the stack bound and calls `morestack`. Moving a stack depends on one invariant, which escape analysis ensures: "the only pointers to stack data are in the stack itself". It also needs precise pointer maps for every frame.
- **Preemption**: until Go 1.14 it was cooperative, at function prologues. Go 1.14 added asynchronous preemption by signal (SIGURG). The innermost frame is then scanned conservatively. One side effect is that more system calls fail with `EINTR`.
- **The collector**: concurrent, tri-color mark and sweep, non-moving, with a write barrier on every heap pointer store. It has been fully precise since 1.4. Stop-the-world pauses have been under 10 ms since 1.5.

Each of these pieces was years of work by a large team.

## 4. What poc does today

### 4.1 The runtime's assumptions

The two `GarbageCollectedHeap` modules (`rtl/llvm/GarbageCollectedHeap.Mod`
and `rtl/vax/GarbageCollectedHeap.Mod`) share a design:

- **Non-moving mark and sweep.** The heap is precise: every object has
  a type tag.
- **Roots** are the modules' globals (through `ModuleTable`) and **one
  stack**, which is scanned conservatively.
  - The stack runs from the current stack pointer up to the base that
    `main` gives `SetStackBase`. The calls are emitted in
    `src/back/llvm/LLVMCodeGenerator.Mod` (lines 8694 and 9075) and in
    `src/back/vax/VaxCodeGenerator.Mod` (line 7609).
  - Callee-saved registers are spilled before the scan, by
    `llvm.eh.unwind.init` on LLVM and by `POC_SAVE_REGISTERS` on the VAX.
- **No locks.** The free lists, the mark bits, the finalizer list and
  the allocation counters are plain globals.
- **Finalizers** run after the collection that finds their object
  unreachable, and once more from `atexit` or the VMS exit handler.

The rest of the runtime makes the same single-thread assumption:
- `Out`, `Err` and `In` buffer their text in globals;
- `Files` keeps a table of open files;
- `Modules` keeps the module list;
- `Texts` and `Oberon` keep their state in globals.

### 4.2 Asynchronous code poc already runs

poc already lets Oberon code run asynchronously in two places:

- **VMS ASTs.** `rtl/vax/AsynchronousTraps.Mod` (`Routine`, `Disable`,
  `Restore`, `InProgress`, `Declare`) and the nine proposals of
  `doc/developer/vax-macro32-backend.md` §22 (approved 2026-10-15):
  - `Allocate`, `Collect` and `RegisterFinalizer` run with ASTs disabled (`SYS$SETAST`).
  - AST-level code must not use `Out`, `Err`, `In` or `Files`.
  - An AST routine runs on the interrupted stack. So the one-stack collector still sees everything, as long as the collector itself is never interrupted.
- **POSIX signals.** `rtl/llvm/Platform.c` (lines 227-238) installs
  `SetInterruptHandler` through `sigaction`, so an Oberon procedure can
  run inside a signal handler. Nothing documents what such a handler may
  call. A handler that allocates while the collector is marking has the
  same hazard that §22 solved on VMS. **[inferred]** This is not
  concurrency, but it is the same reentrancy problem in small. It should
  get §22's rule ("no allocation and no `Out`/`Err`/`In`/`Files` in a
  handler") whatever is decided here.

### 4.3 Probe: POSIX threads from poc today (atla, Fedora, x86-64)

poc compiled a program that starts two threads with `pthread_create`,
declared as an external procedure. The thread body was a top-level
procedure, passed as `SYSTEM.VAL(SYSTEM.ADDRESS, Work)`. The program was
built with `poc -build Threads.Mod -link -lpthread`.

| Program | Result |
|---|---|
| Two threads, each running `NEW` 200,000 times on a list that is cut every 1000 nodes | **Segmentation fault (exit 139) on every run**, at `-opt 2` and at `-opt 0`. The cause was not isolated. There are two candidates, either of them enough on its own: the heap's unlocked free lists, and the collector freeing objects that only the second thread's stack reaches (that stack is never scanned). |
| Two threads, each running `INC(counter)` on a global 5,000,000 times, with no `NEW` | At `-opt 0` it printed 5554202, 5029507 and 5171578 (updates lost, as expected). At `-opt 2` it printed 10000000 every time. Presumably LLVM folded the loop into a single add, so the race window is gone. That shows only how fragile the result is, not that it is safe. |

So **poc's programs cannot use threads today**, even through
`["C"]` declarations. That is the current behaviour, and nothing
documents it.

### 4.4 Probe: DECthreads on the SIMH VAX (VMS 5.5-2H4, 2026-11-13)

The 5.5 New Features Manual (`AA-LA97D-TE...pdf`, ch. 15) introduces
DECthreads. It is "Digital's multithreading run-time library", with
two interfaces:
- CMA (`cma_*`);
- a **POSIX 1003.4a draft** interface (`pthread_*`).

The 5.5 Release Notes (`AA-LB22D-TE...pdf`, §3.9) say its include files
exist **only for C**: other languages declare the routines themselves.
The *Guide to DECthreads* is not held locally.

Two VAX C programs were compiled and linked against
`SYS$SHARE:CMA$OPEN_RTL`, `CMA$RTL` and `VAXCRTL` (all `/SHARE`), and run
as `POC`:

| Program | Result |
|---|---|
| `thrd.c`: two threads, each doing 200,000 increments under `pthread_mutex_lock`, then 200,000 unprotected three-step read-modify-write increments; `pthread_join` | Both threads joined and returned 100 and 101. The locked count was 400,000, which is right. The unprotected count was also 400,000, because each thread ran only about twice, so the race window was never hit. **That proves nothing about safety.** |
| `spin.c`: one thread spins on a flag without blocking, and only a second thread can set the flag | "spinner stopped after 1293550 spins, 0 s: **preempted**". |

Findings:

- **DECthreads on VMS 5.5-2 is preemptive.** It time-slices within one
  process.
- `CMA_CONFIG.H` sets `_CMA_KTHREADS_` to `NONE` on VMS, so its threads
  are user-mode and run on one processor.
- `PTHREAD.H` has the draft-4 interface:
  - attributes are passed **by value** (`pthread_create(&t,
    pthread_attr_default, start, arg)`, `pthread_mutex_init(&m,
    pthread_mutexattr_default)`);
  - an error returns -1 and sets `errno`.

  Today's POSIX threads pass a pointer to the attributes and return the
  error number. **An interface module over both would have to hide that
  difference.**
- The test programs were scratch files, deleted afterwards, and nothing was
  left on the guest.

## 5. Findings

1. **Leaving it out is Wirth's choice.** Oberon was designed without
   concurrency. Coroutines were removed from Modula-2 on purpose, and
   the Oberon system copes with cooperative tasks. Of the Oberons
   still in use, only Active Oberon/A2 (a different language, with its
   own operating system) and oo2c and Linz V4 (as libraries, each with
   caveats) have threads. voc, the reference implementation, has none.
   So nothing about poc is a defect against the report or against voc.

2. **The one portable step the Oberon tradition did standardize is a
   library: Oakwood's `Coroutines`.** ISO Modula-2 has the same thing
   (`COROUTINES`), and so did PIM (`NEWPROCESS`/`TRANSFER`). Both
   Modula-2 and the Modula-3 survey reach the same conclusion: coroutines
   are the one model that fits every target, the VAX included.

3. **Preemptive threads on shared memory are the expensive end.** Each
   implementation that has them paid in the same places:
   - stopping the world: A2 Unix, Linz V4 and CM3 use a signal per thread, Go a signal plus safe points;
   - scanning every thread's registers and stack;
   - a locked heap;
   - a runtime library made reentrant or documented not to be (oo2c);
   - finalizers moved to their own thread (A2);
   - write barriers once the collector is concurrent (Go, A2 optionally).

   For poc that would mean all of section 4.1 at once. It would also
   bring a memory model to define and test on five operating systems
   and three architectures.

4. **The VAX decides the model.** VMS 5.5-2 has no kernel threads.
   DECthreads and DEC Ada both run every thread in one process,
   time-sliced by ASTs. **M:1**, many green threads on one OS thread, is
   therefore the only model the VAX can have. It runs unchanged on the
   LLVM targets too. A Go-like M:N design would make the two back ends
   differ in what a program may assume.

5. **Cooperative switching would make the collector's job almost
   unchanged.** With M:1 scheduling and switches only at known points (a
   `Transfer`, a wait or a blocking call), a collection always starts in
   the running coroutine. Every other coroutine is stopped inside its
   switch routine, with its registers saved on its own stack.
   - The only change: scan each suspended stack from its saved stack
     pointer to its top, as the main stack is scanned now.
   - No heap lock, no stop-the-world and no barrier are needed. A
     program with no second coroutine scans what it scans today.
   - The AST and signal rule of §22 does not change.

   **[inferred]**

6. **Preemption, even M:1, brings the locks back.** DECthreads preempts,
   and so would a timer-driven green-thread scheduler. Then a switch can
   come inside `Allocate` or inside `Out`'s buffer code. On the VAX, the
   AST disabling of §22 might also hold off DECthreads' switches,
   because its time slicing is AST-driven. That is untested, and DEC
   Ada's manual warns that disabling ASTs deadlocks its tasking. On
   POSIX, a timer signal has the same problem as a signal handler today.
   **[inferred]**

7. **The task-creation rule is already settled by poc's language.**
   - A coroutine or thread body must be a procedure value.
   - In poc a procedure value cannot be nested. That rule exists so that
     a body cannot capture an enclosing frame through the hidden
     uplevel pointers.
   - So any of the designs here would start from a top-level procedure
     or a type-bound procedure of a heap object. That is Go's `go f(x)`
     without closures. Ada's "master" rule would be needed only if
     nested bodies were allowed later.
   - Go's moving stacks depend on "the only pointers to stack data are
     in the stack itself". poc's `VAR` parameters and uplevel pointers
     break that rule, so poc's stacks would be **fixed-size with a guard
     page**, as DEC Ada's are.

   **[inferred]**

8. **If language-level concurrency ever comes, two designs are worth
   having:**
   - **Protected objects**, whose Oberon spelling is Active Oberon's
     `EXCLUSIVE`/`AWAIT`.
   - **CSP channels**, as in Go.

   Ada's history argues for protected objects as the primitive. They are
   cheap: no extra task, no queued lock, and the proxy model. They also
   fit Oberon-2's records and type-bound procedures. Channels and
   `select` can then be a library built on them. The reverse direction
   costs more, per the Ada 83 Rationale. A Ravenscar-like subset is the
   smallest form that is safe to have.
   - Every language that has shared memory makes a data race
     *erroneous* (Ada 83 9.11, Ada 2022 9.10) or *undefined* (Go,
     beyond DRF-SC). Go adds that races on multiword values corrupt
     memory. In poc those values would be open-array dope vectors,
     procedure values and type tags.
   - Ada 2022 checks conflicts at compile time by default, and Brinch
     Hansen argues for that: a structure the compiler can check, not
     opt-in locking.

9. **What does not fit poc:**
   - **`ucontext`**: OpenBSD does not provide it, which is why CM3's
     user threads do not build there.
   - **gm2's coroutine-as-pthread**: it brings back every cost of
     finding 3 for the semantics of finding 2.
   - **LLVM's coroutine intrinsics**: they are stackless, so they cannot
     `Transfer` from inside nested calls.

   The context switch would instead be a few instructions per
   architecture: x86-64, i386 and arm64 in `rtl/llvm/*.c` with inline
   assembly, and VAX MACRO-32 in `PocRtl.mar`. **[inferred]** On the
   VAX it is especially simple. The probe of section 8 found it
   simpler still: a routine whose entry mask saves R2-R11 stores its
   FP, loads the other coroutine's FP and does `RET`, which restores
   SP, AP and the registers from the other stack's frame. A new
   stack's first frame is chained to `main`'s (section 8.3, items 4
   and 7).

## 6. Options and proposal

| | Option | What a program gets | Cost to poc | Both back ends? |
|---|---|---|---|---|
| A | **Leave concurrency out** (status quo, documented) | Nothing new. The guides say threads are unsupported, and why (section 4.3). | One paragraph in `language-extensions.md` and the Reference Guide. A rule for signal and AST handlers. | yes |
| B | **Coroutines library** (Oakwood §1.2.8 interface, maybe with ISO Modula-2's names for the extras) | Explicit `Transfer` between coroutines with fixed stacks. A cooperative scheduler, generators and pipelines can be written in Oberon on top of it. | A runtime module and one context-switch routine per architecture (four). The collector scans a list of suspended stacks, empty unless the module is used. A hook in the collector. Stacks get guard pages (`mmap` with `MAP_STACK` on OpenBSD; on VMS `LIB$GET_VM_PAGE` and `$SETPRT`; both verified, section 8). No compiler change. | yes |
| C | **B plus a cooperative task library**: `Tasks` with spawn, yield, join, monitors/conditions and channels, written in Oberon over B. Blocking I/O wrapped as DEC Ada's `TASKING_SERVICES` does: asynchronous `SYS$QIO` plus an AST that wakes the task; `poll` on POSIX. | Go-like structure without parallelism or preemption. Atomicity between switch points is guaranteed. | B, plus the library, plus wrappers around `Files`, `In` and the console for each OS. No compiler change. | yes |
| D | **Language-level tasks and monitors** (`EXCLUSIVE`/`AWAIT` à la Active Oberon, or protected types à la Ada) | Checked structure: shared data reachable only through the monitor's operations. | A Phase-sized extension: syntax, checker, `.sym`, both code generators, a shared-variable rule in `language-extensions.md`, `-strict` rejecting it. It needs C's runtime underneath. | yes, if built on C |
| E | **Preemptive OS threads** (POSIX threads; DECthreads on VMS) | Real parallelism on the LLVM targets, but not on the VAX (DECthreads there is single-processor). | Stop-the-world, scanning of every thread's stack, a heap lock, a reentrant runtime library, finalizers on their own thread, a memory model, and a draft-4 vs. final pthread shim on VMS. Effectively a new runtime. | in name only |

**Proposal [inferred]:**

1. **Now, whatever else is decided: option A's documentation.**
   - Say that poc's programs may not create threads, and why.
   - Give signal handlers (`Platform.SetInterruptHandler`) the AST rule
     of §22: no `NEW`, no `Out`/`Err`/`In`/`Files`.

   This fixes a gap that exists today.

   **Done 2026-11-13** (`language-extensions.md`, "Threads and signal
   handlers"). Writing it found one more rule: the main line must read
   the handler's variable by `SYSTEM.GET`, since at `-opt 1` and up LLVM
   loaded it once in `WHILE ~interrupted DO INC(n) END`, and the loop
   never ended.
2. **If the user wants concurrency at all: option B as a runtime
   module**, through `PLAN.md`'s "Ongoing library enhancements".
   - It is the step the Oberon tradition itself standardized.
   - It costs nothing for a program that does not import it.
   - It needs no change to the language or the checker, and it runs the
     same on every target, the VAX included.

   Section 8 probed it on x86-64, i386 and the VAX: a round trip by
   `Transfer` costs about 20 procedure calls (8 on the VAX), and the
   guard pages, a returning body (exit 16) and the VMS frame chain
   (chained to `main`'s) are settled there. Its open design points are
   now:
   - how a stack is freed (section 8.3, item 3);
   - whether the collector's stack list belongs in
     `GarbageCollectedHeap` or in the new module;
   - whether the switch saves the floating-point control registers.
3. **Option C is the natural next step after B** and can wait until
   programs ask for it. It too is a library, not a language change.
   Section 9 sketches one possible interface for it.
4. **Options D and E: not adopted.**
   - D would be worth reconsidering only after C has been used. That
     use would show whether the checked structure is worth a language
     extension.
   - E costs the most and gives the least on the VAX. It runs against
     both the Oberon tradition and the "cost only for users" rule,
     because a thread-safe heap and runtime would cost every program.

## 7. Not verified, and to do before any implementation

- Hoare 1978, the occam manual and Zonnon's report were not read in the
  original.
- Ada 2022 has no Rationale. Its place is taken by Cousins's *Overview
  of Ada 2022*, which was read for chapter 2 and §6.10. Jorvik's AI
  (AI12-0291) itself was not read.
- Whether GNAT implements `parallel` was not checked.
- Go's GC pacer document was not read.
- Whether disabling ASTs (`SYS$SETAST`) holds off DECthreads' time
  slicing on VMS 5.5-2 was not tested. The *Guide to DECthreads* for 5.5
  is not held. It is the manual to fetch if option E is ever on the
  table on the VAX; add it to `vax-vms-manuals-to-get.md` then.
- OpenBSD's `MAP_STACK` requirement was verified on cymoril
  (section 8.3, item 5).
- A VMS coroutine stack's allocation and guard page were taken from
  the VMS 5.0 RTL Library (LIB$) and 5.5 System Services manuals and
  verified on the VAX (section 8.3, item 5). For stacks over 1000
  pages the LIB$ manual recommends `$EXPREG` instead, which was not
  tried.
- The cause of the segfault in section 4.3 was not isolated. It does not
  matter for the proposal, because both candidate causes are present.

## 8. Option B probed: what it costs, and what implementing it needs

Added 2026-11-13, at the user's request: how a coroutines library
would affect the performance of the programs that use it, and what
implementing it would take, found by exploratory programming, without
starting on B itself. The prototype was built in a scratch directory
and is not in the tree. Its parts were:

- a module `Coroutines` with Oakwood's interface (`Init(body,
  stackSize, VAR cor)`, `Transfer(VAR from, to)`);
- a context switch for x86-64, i386 and arm64 in C with inline
  assembly, and for the VAX in MACRO-32;
- a copy of each back end's `GarbageCollectedHeap` with a hook for
  the suspended stacks (8.3, item 1);
- four test programs:
  - `Ping`: a generator, and a body that returns;
  - `GcTest`: each of two stacks holds a list that nothing else
    points to, while the other one allocates enough to collect many
    times;
  - `Fail`: a NIL trap, a stack overflow, `HALT` and (on the VAX) an
    access violation, each on a coroutine;
  - `Bench`: the timings below.

### 8.1 Where it ran

| Host | System, word size | Ran |
|---|---|---|
| atla | Linux (Fedora 44), x86-64 | everything, at `-opt 0` and `-opt 2`, and with `-lto` |
| artos | NetBSD 11.0, amd64 (VM) | everything, with and without `MAP_STACK` |
| alerik | FreeBSD 15.1, amd64 (VM) | everything, with and without `MAP_STACK` |
| jherek | OpenBSD 7.9, amd64 (VM) | everything, with and without `MAP_STACK`, with the installed poc 0.11.2 |
| cymoril | OpenBSD 7.9, i386 (VM) | everything, with and without `MAP_STACK` |
| yishana | NetBSD 11.0, i386 (VM) | everything, with and without `MAP_STACK`, with the installed poc 0.11.2 |
| rackhir | FreeBSD 15.1, arm64 (VM, emulated on atla) | everything, with and without `MAP_STACK` |
| SIMH MicroVAX 3900 | VAX/VMS 5.5-2H4 | everything, with two ways to end a new stack's frame chain |

alerik and rackhir ran it later the same day, and jherek and yishana
after them, as each came back up. jherek and yishana have no source
tree, so their runs used the installed poc 0.11.2, whose `rtl/llvm` is
the one the prototype patched.

### 8.2 Performance

**What a program pays for using it [measured].** All times are per
operation, at the default `-opt` (2, but 0 on i386), from 10^5 to
10^6 repetitions:

| | atla x86-64 | artos amd64 | alerik amd64 | jherek amd64 | cymoril i386 | yishana i386 | rackhir arm64 (emulated) | rackhir, as procedure calls | VAX (SIMH) |
|---|---|---|---|---|---|---|---|---|---|
| Procedure-variable call, for scale | ~1 ns | 1 ns | 1 ns | ≤1 ns | 2 ns | 2 ns | 28 ns | 1 | ~0.3 µs |
| `Transfer` there and back (two switches) | 21-22 ns | 23 ns | 22 ns | 24-25 ns | 34 ns | 29 ns | 410 ns | ~15 | ~2.4 µs |
| `swapcontext` there and back, for comparison | 256-281 ns | 1268 ns | 1041 ns | (none: OpenBSD has no `ucontext`) | (none) | 1488 ns | 8569 ns | ~306 | — |
| `Init` (allocate a stack, protect its guard page) | ~2.5 µs | ~2.0 µs | ~25 µs | ~5 µs | ~13 µs | ~3.2 µs | ~27 µs | ~956 | ~70 µs |
| First `Transfer` to a new stack (touches its first page) | ~125 ns | ~148 ns | ~135 ns | ~220 ns | ~251 ns | ~196 ns | ~533 ns | ~19 | below the clock's resolution |

rackhir's absolute times are the emulator's, so only its ratios mean
anything. Its second column gives them, each time divided by its
procedure-variable call: a round trip costs about 15 procedure calls,
and `swapcontext` 21 times as much as `Transfer`. jherek's procedure
call measured 0 ns in one run and 1 ns in the other.

- **A round trip by `Transfer` costs about 20 procedure-variable calls
  on x86, and 8 on the VAX.** Most of it is saving and restoring the
  callee-saved registers, plus `Transfer`'s own bookkeeping in Oberon
  (`SetStackBase`). Saving the x86 floating-point control registers
  (MXCSR and the x87 control word) adds 2-3 ns of the 21-22.
- **That is 10-50 times cheaper than `swapcontext`.** `swapcontext`
  makes a `sigprocmask` system call on every switch. The VAX's 2.4 µs
  is CPU time from `F$GETJPI("","CPUTIM")`, whose unit is 10 ms, over
  10^5 round trips. It is two `CALLS` with a ten-register entry mask
  and two `RET`s, plus `Transfer`'s code.
- **`Init` is a system call or two.** That is `mmap` plus `mprotect`,
  or `LIB$GET_VM_PAGE` plus `$SETPRT` on the VAX. A program that makes
  a coroutine per item, and not per task, would pay for that. A pool
  of stacks would be a library's answer [inferred].
- **On the VAX the first `Transfer` costs no more than any other, as
  far as the clock can tell.** Six runs each of 1000 and 1900 `Init`s,
  with and without a first `Transfer` to each new stack and straight
  back, took 63 and 69 centiseconds in all over 8700 of each: no
  difference within the 10 ms unit, so the first switch is a round
  trip (2.4-3.7 µs, by the run) plus less than about 10 µs. There is a
  reason it is cheap: `CORO_NEW` writes the stack's first frame into
  its top page, so `Init` has already touched the page the first
  `Transfer` lands on. The same runs showed how coarse the clock is:
  1900 `Init`s took 10-17 cs, no more than 1000 did (10-11 cs).

**Memory [measured on atla].** A stack's size is reserved address
space. Only the pages the coroutine touches become memory:

- 10000 coroutines with 64 KiB stacks, each switched to once, raised
  the resident size by 40 MB, 4 KiB each, and the virtual size by
  680 MB.
- **OpenBSD counts the stacks against the data limit.** On cymoril
  (i386) and jherek (amd64) alike, a second batch of 10000 64 KiB
  stacks (20002 in all, about 1.3 GB) could not be mapped under the
  runs' 1 GB `ulimit -d`. jherek mapped them at its default 1.5 GB, and
  cymoril at its hard limit of 3 GB, so on both the data limit refused
  them, not the address space [measured]. On a 32-bit host the address
  space is still the eventual bound: yishana (NetBSD i386) mapped all
  20002.
- On the VAX each stack is pages of P0 space. They count against the
  process's virtual-memory quotas as the heap's do; how much was not
  measured.

**What a collection pays [measured].** The collector must scan every
suspended stack, from its saved SP to its top (8.3, item 1), so the
cost grows with how many bytes of stack are suspended. Each host ran
the benchmark twice, at its default `-opt` and with its whole hard
data limit; a range is the two runs:

| Collection of 100000 live objects | atla | artos | alerik | jherek | cymoril (`-opt 0`) | yishana (`-opt 0`) | rackhir (emulated) | rackhir, as its first row |
|---|---|---|---|---|---|---|---|---|
| no coroutines (main stack only) | 1.20-1.32 ms | 1.30-1.41 ms | 1.29-1.30 ms | 1.91-1.97 ms | 10.0-13.3 ms | 9.3-9.6 ms | 8.2-9.4 ms | 1 |
| + 10000 suspended stacks, each a few frames deep | 1.81-1.85 ms | 1.78-2.27 ms | 1.91-1.98 ms | 2.50-2.66 ms | 14.6-15.6 ms | 12.5-14.2 ms | 14.8-15.5 ms | 1.7 |
| + 10000 more, each 100 frames deep | 8.04-8.09 ms | 7.64-9.54 ms | 8.35-8.44 ms | 10.6-12.2 ms | 111.4-111.5 ms | 103.0-110.7 ms | 111.8-111.9 ms | 12.7 |

How many bytes the collector scanned, the sum over the suspended
stacks of their top less their saved SP (the coroutine that echoes
`main` included), was the same on every host of an architecture:

| Suspended stack scanned | x86-64, `-opt 2` (atla, artos, alerik, jherek) | i386, `-opt 0` (cymoril, yishana) | arm64, `-opt 2` (rackhir) |
|---|---|---|---|
| + 10000 shallow stacks | 1.28 MB (about 128 bytes a stack) | 2.32 MB (232) | 2.24 MB (224) |
| + 10000 deep stacks | 50.56 MB (4928 bytes more a stack, about 49 a frame) | 84.64 MB (8232, about 82 a frame) | 52.48 MB (5024, about 50 a frame) |

So the cost is about 0.13 ns a byte, 1 ns a word, on the x86-64 hosts
at `-opt 2` (6.2 ms for 49.3 MB on atla), and about 1.1-1.2 ns a byte
on the i386 hosts at `-opt 0`, where the runtime library is compiled
at `-opt 0` too. Ten thousand shallow stacks add about half a
millisecond to a collection on x86-64; 50 MB of deep ones add 6-7 ms.
A program with tens of coroutines would not notice either.

A first version of this benchmark measured something else in its last
row. Its recursive procedure ended in the recursive call and never read
its local array, so at `-opt 2` LLVM made the recursion a loop, and its
"100 frames deep" stacks were about 112 bytes each: the row showed
2.2-3.1 ms on the x86-64 hosts and 24.8 ms on rackhir, and only
yishana, at `-opt 0`, scanned deep stacks (97.7 ms), which made it look
out of line with the rest. The version measured above reads the array
after the call, and the scanned bytes confirm the stacks' depth.

**What a program that does not use it pays [measured].** It pays one
test of a procedure variable for NIL per collection, the heap's hook.
That fits "cost only for users". Nothing else changes: no compiler
change, and no code in `Transfer`'s absence.

### 8.3 What implementing B needs

1. **A hook in `GarbageCollectedHeap`, on both back ends.** This is the
   one change outside the new module, and it cannot be avoided. Each
   collector marks from the running stack, from the current SP up to
   `stackBase`, which `main` records. `GcTest` shows what goes wrong
   without the hook [measured, every host]:

   - **With no support** (mode 0), the scan runs from a coroutine's
     stack up to the main stack's base, across unmapped memory. On
     Linux, NetBSD and OpenBSD it crashed (SIGSEGV or SIGBUS), and on
     the VAX it got ACCVIO after one list had already been freed. On
     FreeBSD, amd64 and arm64 alike, it did not crash: it lost both
     lists as mode 1 does. Why the scan did not fault there was not
     isolated.
   - **Moving `stackBase` on each `Transfer`, but not scanning the
     suspended stacks** (mode 1), freed each side's list while the
     other side ran: "1 wrong, 9999 missing". The program did not
     crash and printed wrong results, the worst outcome.
   - **Moving `stackBase` and scanning every suspended stack** from
     its saved SP (the VAX: its saved FP) to its top (mode 2) kept
     both lists through 64-389 collections. That held on every host,
     at `-opt 0` and with `-lto` too.

   The prototype's hook is four exports:
   - `MarkRange(low, high)`, which marks candidates in a range;
   - `StackBase()`;
   - `SetStackScanner(p)`;
   - a call `IF stackScanner # NIL THEN stackScanner END` after
     `MarkFromStack`.

   A suspended stack's callee-saved registers are covered without more
   work, because the switch pushes them onto that stack (on the VAX,
   `CALLS` saves them in the switch routine's frame).

   Whether the list of stacks lives in the heap or in the new module is
   a choice. A stack that the heap knows about could also be freed by
   it (item 3).

2. **A `Coroutine` must name a descriptor, not hold the stack's
   state.** Records can be copied, and `Transfer(VAR from, to)` writes
   `from`. The prototype keeps a table of stacks (SP, low, high) and
   puts an index in the record. The real module would put a pointer to
   a descriptor there [inferred].

3. **Freeing a stack is not solved.** Oakwood has no `Free`, a record
   has no finalizer, and the prototype frees nothing. There are two
   ways:
   - **An explicit `Free` extension.** It is simple. A program that
     frees a stack it later transfers to fails as a dangling pointer
     does.
   - **A collected descriptor.** The heap would scan a suspended stack
     only when its descriptor has been marked, not as a root, and free
     the stack when the descriptor dies. Otherwise a stack that holds
     a pointer to its own descriptor keeps itself alive. That needs a
     mark-time hook per object, and more heap change than item 1.

   On the VAX, the guard page's protection must be restored before the
   pages go back by `LIB$FREE_VM_PAGE` [inferred].

4. **A context switch per architecture, and a first frame for a new
   stack.** Each is a few instructions:

   | Target | Saved | First frame |
   |---|---|---|
   | x86-64 | RBP, RBX, R12-R15, MXCSR, x87 control word: 9 words | returns into a trampoline with the body in R12 |
   | i386 | EBP, EBX, ESI, EDI, x87 control word: 7 words | the body in EBX |
   | arm64 | X19-X30, D8-D15, FPCR: 176 bytes | the body in X19, the trampoline in X30 |
   | VAX | R2-R11 by the entry mask: `MOVL FP,@4(AP)`, `MOVL 8(AP),FP`, `RET` | a fake `CALLS #0` frame: mask `^X2FFC0000`, saved PC the trampoline, saved R2 the body |

   - **The trampoline calls the body.** If the body returns, which
     Oakwood forbids, the program ends with status 16, "coroutine body
     returned" (on the VAX `%X10000082`, as poc's traps map status
     16). This ran on every host.
   - **The floating-point control registers are optional.** poc gives
     a program no way to change the rounding mode or the exception
     masks. A module's C part could, though, and saving the registers
     costs 2-3 ns.
   - **On the VAX the switch is three instructions.** The entry mask
     saves the registers, and `RET` through the other stack's frame
     restores everything, AP and PSW included.

5. **Stacks with a guard page below.**
   - **POSIX**: `mmap` with `MAP_PRIVATE | MAP_ANON`, then `mprotect`
     of the lowest page to `PROT_NONE`.
   - **OpenBSD needs `MAP_STACK` [measured].** Without it, `Ping`'s
     transfers worked until the coroutine made its first system call
     (writing output, or the heap asking for memory). Every program
     then died with SIGSEGV, because OpenBSD checks that SP is in a
     `MAP_STACK` mapping at system-call entry. OpenBSD 7.9's `mmap(2)`
     documents the flag but not that rule. It holds on amd64 (jherek)
     as on i386 (cymoril). NetBSD (amd64 and i386) and FreeBSD (amd64
     and arm64) run the same programs without it.
   - **VMS**: `LIB$GET_VM_PAGE` gives page-aligned pages (*VMS 5.0
     RTL Library (LIB$) Manual*, chapter 5). `$SETPRT` with `PRT$C_NA`
     and equal start and end addresses protects one page (*VMS 5.5
     System Services Reference Manual*, SYS-529). Both worked.

6. **What ends a program on a coroutine [measured]:**

   | | LLVM | VAX |
   |---|---|---|
   | NIL dereference | the trap's message (with `-trap-location`, its place and procedure), the finalizers, exit 4 | `%X10000022` (trap 4) |
   | `HALT(3)` | the finalizers, exit 3 | `%X1000001A` |
   | stack overflow into the guard page | SIGSEGV (139), as on the main stack | ACCVIO, see item 7 |
   | access violation | not tried (SIGSEGV) | see item 7 |

   poc's traps and `HALT` do not depend on the stack they run on. On
   the VAX `POC_TRAP` leaves by `$EXIT` itself and needs no condition
   handler.

7. **On the VAX, where a new stack's frame chain ends.** The calling
   standard says the search for a condition handler "ends when the old
   FP is 0 or is not accessible" (*Introduction to VMS 5.4 System
   Routines*, AA-LA66B, 2-48). The system's catch-all and traceback
   handlers sit in frames below `main`'s. Both ways were tried with an
   access violation on a coroutine:
   - **Saved FP 0**: no handler is found. The last-chance handler
     prints "Improperly handled condition, image exit forced" and a
     register dump, and there is no traceback.
   - **Saved FP set to `main`'s frame**, which is the `stackBase` that
     `main` passes: the normal `%TRACE-F-TRACEBACK` lists the
     coroutine's frames (the body, then the trampoline), and the image
     exits `%X1000000C`.

   Chaining to `main` is the better choice [inferred]. Its risk is a
   handler that unwinds (`$UNWIND`) past the coroutine's frames, which
   would land on the main stack's frames while SP is on the coroutine's
   stack. poc's own code establishes no such handler, but a program's
   `["VMS"]` code could.

   A **stack overflow** ends the image with ACCVIO either way, with two
   dumps, because delivering the exception needs room on the stack that
   has none. The main stack does not have this problem, since VMS
   extends it. A clean message would need the overflow caught before
   the guard page, by a check in each procedure's prologue, which is a
   compiler change and not worth it for B [inferred].

8. **Rules for programs, to document [inferred]:**
   - **No `Transfer` from a signal handler or an AST.**
   - **Room on every stack for handlers.** A signal handler (LLVM) or
     an AST (VMS) runs on whichever stack is current, so every
     coroutine's stack needs room for one.
   - **Bodies never return.**
   - **The stack size is fixed.** There is no growth, as DEC Ada's task
     stacks have none.

9. **Things that would break it [inferred]:**
   - **Shadow stacks.** Intel CET's shadow stack (and arm64's GCS)
     would reject the switch's `ret` to another stack. poc's objects
     carry no `-fcf-protection` notes, so the kernel does not enable
     it today. If poc ever adds the notes, the switch would need the
     shadow-stack instructions.
   - **Debuggers.** gdb's backtrace and VMS DEBUG's `SHOW CALLS` on a
     coroutine were not tried.

10. **No compiler change.**
    - A body is passed as `SYSTEM.VAL(SYSTEM.ADDRESS, body)` to an
      external routine.
    - Nested and type-bound procedures cannot be procedure values
      already, so a body is always a global procedure.
    - The optimizer treats the external switch as an opaque call, so
      it reloads globals after it.

**Size of the work [inferred]:** about 150 lines of Oberon, 150 of C
and 40 of MACRO-32, plus the heap's hook on both back ends, the
fixtures (the four programs above, made to compare output), the
guides.

### 8.4 Coroutines, I/O and C libraries

Added 2026-11-13, at the user's request, before B's plan: how
coroutines meet I/O and C libraries, with pofltk (the FLTK binding for
poc, Unix only, never VMS) as the case in point. Nothing here was run.
It rests on the measurements above, pofltk's `Fl.Mod` and FLTK's
design, and all of it is **[inferred]**.

Under B the one new fact is that code runs on stacks other than the
main one. There is still one thread and no preemption, so whatever a
program could do between two calls before, it still can.

1. **A blocking call stops every coroutine.** `In.Line`,
   `Files.ReadBytes`, an RMS `$GET`, `Fl.Run` or `Fl.Wait`: whichever
   coroutine makes the call, the whole program waits. B has no
   scheduler, so that is what B means, not a defect, and its
   documentation says so. Getting around it is C's job (an `Event`
   over `poll` or a `$QIO` AST, section 9). A GUI program already has
   a way: FLTK's `Fl.AddFd` and its timeouts make FLTK's event loop
   the place the program waits.

2. **The runtime's I/O is safe because it never switches.** `Out`'s
   buffer, `Files`' buffers, `Texts` and the heap keep global state,
   and no runtime module calls `Transfer`, so no switch comes in the
   middle of one of their operations. Output from several coroutines
   comes out in the order of the calls. The runtime calls a program's
   own code in three places, and each needs a rule:
   - **finalizers**: no `Transfer` (they run from the collector or
     from `atexit`);
   - **signal handlers and ASTs**: no `Transfer` (8.3, item 8);
   - **`Modules` commands**: ordinary calls, no rule.

3. **C code on a coroutine's stack** runs as it does on the main
   stack, with four differences:
   - **Stack size.** C libraries can use far more stack than Oberon
     code: fontconfig, Xft, Cairo, libpng and FLTK's layout and
     drawing never run short on the main stack, but could overflow a
     64 KiB coroutine's (SIGSEGV). Only touched pages cost memory
     (8.2), so a coroutine that calls C can have 1 MiB for little more
     than its pages. Item 4's pattern (a) avoids the question.
   - **One guard page.** A C frame with more than 4 KiB of locals can
     step over it into the memory below ("stack clash"). Fedora builds
     its system libraries with stack-clash probing; the BSDs, an FLTK
     a program builds itself, and clang's defaults may not. A larger
     guard area, or "big C on big stacks", helps.
   - **The collector** scans a suspended stack from its saved SP up,
     C frames included, so a pointer held only in a C frame is still
     seen. One held only in C's heap is still not seen, as today:
     that is why pofltk keeps its registry.
   - **No exception or `longjmp` across a switch.** Each must start
     and end on one stack. libpng's error handling and FLTK's image
     loading use them inside a call, which is fine. A C++ exception
     that reaches the trampoline at a coroutine's base ends in
     `std::terminate`. pofltk's `Fl.cpp` has no `try` or `catch`.

4. **Switching out of a callback, with pofltk as the case.** FLTK
   calls Oberon (`Callback`, `Handle`, `Draw`, a timer's `Fire`) from
   inside `Fl.Run`. There are two ways to use coroutines with it:
   - **(a) FLTK owns the main stack, and callbacks resume
     coroutines.** A button's `Callback` does `Transfer(main,
     script)`; the script coroutine runs until it needs the next
     input, then `Transfer(script, main)`, and the callback returns to
     FLTK. FLTK's frames are left exactly as they were. This is the
     useful pattern, a dialog written as straight-line code instead of
     a state machine, and it keeps FLTK's deep drawing on the main
     stack. A coroutine may call widget methods: that is the callback
     calling them.
   - **(b) A coroutine is suspended with FLTK's frames on its
     stack**: a callback switches away and does not come straight
     back. FLTK is part way through dispatching an event, which is
     safe only if nothing changes FLTK's state before the coroutine is
     resumed and returns:
     - FLTK's event state is global (`Fl.Mod`: "while Handle runs,
       the Event procedures below say what the event was"). Another
       coroutine's `Fl.Wait` overwrites it, so a `Handle` reads what
       it needs before it switches.
     - A nested `Fl.Wait` from another coroutine is FLTK's
       modal-dialog case and is allowed, but a widget deleted
       meanwhile leaves the suspended frames pointing at freed memory.
       FLTK's deferred `Fl::delete_widget` and `Fl_Widget_Tracker`
       exist for that.
     - A stack never resumed leaves FLTK mid-dispatch for good, and
       C++ destructors on it never run. If B gets a `Free` (8.3,
       item 3), freeing a stack with C frames on it is the same
       problem.

   (a) is the way to document. The rule for (b), for any C library
   that calls back into Oberon: a coroutine that switches out of a C
   callback must be resumed, and must return to C, before anything
   else uses that library.

5. **VMS.** pofltk does not apply, but the same questions do:
   - RMS runs in executive mode on its own stack, so it needs less of
     a coroutine's stack than C does, but it still blocks the process.
   - An AST is delivered on whichever stack is current (8.3, item 8),
     and may set a flag but not `Transfer`.
   - A `LIB$` routine's condition handler that calls `$UNWIND` could
     unwind onto the wrong stack, since a coroutine's frames are
     chained to `main`'s (8.3, item 7).

6. **What it means for C.** The scheduler's wait for something to
   happen must be replaceable. A pofltk program already waits in
   FLTK's loop (`Fl.Wait`, `AddFd`, timeouts), and a `Tasks` with its
   own `poll` loop would compete with it. So `Tasks` should either be
   able to use `Fl.Wait` as its idle step, or let FLTK own the loop
   and resume tasks from callbacks, pattern (a). pofltk is Unix only,
   so this is a hook in `Tasks`, not a dependency on pofltk.

**To settle before B's plan:**

1. B documents that a blocking call stops every coroutine, and has no
   I/O wrappers.
2. `Transfer` is forbidden in signal handlers, ASTs and finalizers.
3. Switching out of a C callback is allowed, under item 4's rule.
4. The default stack size: larger than 64 KiB on the LLVM targets,
   where it is cheap. On VMS, `LIB$GET_VM_PAGE` charges the page-file
   quota for the whole stack, so a smaller default fits there.
5. A pofltk probe before the plan is final:
   - pattern (a) with a script coroutine;
   - the main stack's high-water mark in a typical pofltk program, to
     size a coroutine stack that calls FLTK;
   - a nested `Fl.Wait` from a coroutine, to see whether (b) is
     workable at all.

### 8.5 An example program: WordSets

Added 2026-11-13, at the user's request: a program written with
Oakwood's interface that is useful and runs unchanged on Unix and VMS.
It has not run, since B's `Coroutines` is not in the tree, but it
type-checks with poc against a stub with Oakwood's interface (8.6). It
would make a fixture and a guide example once B is built.

It is the classic coroutine problem, "same fringe" (walk two trees in
order, in step), made into a word-set comparer: it reads the words of
two text files and says which are only in the first (`<`), only in the
second (`>`), or in both (`=`). With a document and a word list as the
two files, the `<` lines are a spelling checker.

Coroutines are what make it simple. An in-order walk is naturally
recursive, and the merge must advance two walks alternately. Without
coroutines each walk would have to be rewritten with an explicit stack
or with parent pointers; with them each is the ordinary recursive
procedure on its own stack, handing over one word at a time.

```oberon
MODULE WordSets;  (* which words are in one file, the other, or both *)

  IMPORT Coroutines, Files, Args, Out;

  CONST maxWord = 64;

  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      word: ARRAY maxWord OF CHAR;
      left, right: Node
    END;
    Walker = RECORD
      cor: Coroutines.Coroutine;
      tree: Node;
      current: Node   (* the word handed over; NIL after the last *)
    END;

  VAR
    main: Coroutines.Coroutine;
    a, b: Walker;
    name: ARRAY 256 OF CHAR;

  PROCEDURE Insert(VAR t: Node; VAR word: ARRAY OF CHAR);
  BEGIN
    IF t = NIL THEN NEW(t); COPY(word, t.word)
    ELSIF word < t.word THEN Insert(t.left, word)
    ELSIF word > t.word THEN Insert(t.right, word)
    END
  END Insert;

  PROCEDURE IsWordChar(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (CAP(ch) >= "A") & (CAP(ch) <= "Z") OR (ch >= "0") & (ch <= "9")
  END IsWordChar;

  PROCEDURE ReadWords(name: ARRAY OF CHAR; VAR tree: Node);
    VAR f: Files.File; r: Files.Rider; ch: CHAR;
      word: ARRAY maxWord OF CHAR; i: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN
      Out.String("cannot open "); Out.String(name); Out.Ln; HALT(1)
    END;
    Files.Set(r, f, 0); Files.Read(r, ch);
    WHILE ~r.eof DO
      IF IsWordChar(ch) THEN
        i := 0;
        REPEAT
          IF i < maxWord - 1 THEN word[i] := ch; INC(i) END;
          Files.Read(r, ch)
        UNTIL r.eof OR ~IsWordChar(ch);
        word[i] := 0X; Insert(tree, word)
      ELSE Files.Read(r, ch)
      END
    END
  END ReadWords;

  PROCEDURE Height(t: Node): LONGINT;
    VAR l, r: LONGINT;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    l := Height(t.left); r := Height(t.right);
    IF l > r THEN RETURN l + 1 ELSE RETURN r + 1 END
  END Height;

  (* The walk: ordinary in-order recursion, handing each node to main. *)
  PROCEDURE Walk(t: Node; VAR w: Walker);
  BEGIN
    IF t # NIL THEN
      Walk(t.left, w);
      w.current := t; Coroutines.Transfer(w.cor, main);
      Walk(t.right, w)
    END
  END Walk;

  (* A body must not return: after the last word, hand over NIL forever. *)
  PROCEDURE Finish(VAR w: Walker);
  BEGIN
    w.current := NIL;
    LOOP Coroutines.Transfer(w.cor, main) END
  END Finish;

  PROCEDURE WalkA; BEGIN Walk(a.tree, a); Finish(a) END WalkA;
  PROCEDURE WalkB; BEGIN Walk(b.tree, b); Finish(b) END WalkB;

  PROCEDURE Next(VAR w: Walker);
  BEGIN Coroutines.Transfer(main, w.cor)
  END Next;

  PROCEDURE Show(mark: CHAR; n: Node);
  BEGIN Out.Char(mark); Out.Char(" "); Out.String(n.word); Out.Ln
  END Show;

BEGIN
  IF Args.argc # 3 THEN
    Out.String("usage: wordsets file1 file2"); Out.Ln; HALT(2)
  END;
  Args.Get(1, name); ReadWords(name, a.tree);
  Args.Get(2, name); ReadWords(name, b.tree);
  (* A walk is as deep as its tree is high; sorted input makes a list. *)
  Coroutines.Init(WalkA, 16384 + 256 * Height(a.tree), a.cor);
  Coroutines.Init(WalkB, 16384 + 256 * Height(b.tree), b.cor);
  Next(a); Next(b);
  WHILE (a.current # NIL) OR (b.current # NIL) DO
    IF (b.current = NIL) OR (a.current # NIL) & (a.current.word < b.current.word) THEN
      Show("<", a.current); Next(a)
    ELSIF (a.current = NIL) OR (b.current.word < a.current.word) THEN
      Show(">", b.current); Next(b)
    ELSE
      Show("=", a.current); Next(a); Next(b)
    END
  END
END WordSets.
```

**Why it runs unchanged on Unix and VMS:**

- **Only portable modules.** It uses only `Files`, `Args` and `Out`,
  which have the same interface in `rtl/llvm` and `rtl/vax`.
- **Line ends.** On VMS, `Files.Old` reads a variable-length or VFC
  text file a record at a time, with a line feed after each record
  (`rtl/vax/Files.Mod`), so the word scanner sees the same text on both
  systems.
- **Running it on VMS.** It runs as a foreign command, for example
  `WORDSETS :== $DEV:[DIR]WORDSETS.EXE`, then `WORDSETS MEMO.TXT
  WORDS.TXT`.

**How it follows 8.4's rules [inferred]:**

- **I/O stays on the main stack.** All reading and output happen
  there; the coroutines only walk trees, so nothing blocks on a
  coroutine's stack and no C or RMS code runs there.
- **Bodies never return.** `Finish` hands over `NIL` forever, as
  Oakwood requires.
- **Stack size comes from the data.** Each walk's recursion is as deep
  as its tree is high. Sorted input turns the unbalanced tree into a
  list, so a sorted 10000-word dictionary needs a deep stack. The
  program measures the height and sizes each stack from it before
  `Init`. On Unix that costs only the pages actually touched. On VMS
  the whole stack is charged against the page-file quota, which
  matters for very large inputs; a balanced tree would avoid both.

### 8.6 A second example: k queens on an n×n board

Added 2026-11-13, at the user's request, and generalized the same day
from the eight queens: place `k` queens on an `n`×`n` board so that none
attacks another, with `n` from 1 to 26 and `k` from 1 to `n`. With the
defaults (`n` = `k` = 8) it is the classic eight queens problem. It is
written with Oakwood's interface and, like 8.5, runs unchanged on Unix
and VMS.

**What was checked.** The program has not run with coroutines, since B's
module is not in the tree. It type-checks with poc against a stub
`Coroutines` that has only Oakwood's interface, under `-strict` and `-O2`
as well (and so does 8.5's WordSets). The search, the boards and the
argument checks ran on atla, in a variant that calls `Show` from `Place`
instead of transferring. It found the counts in the table below, which
agree with an independent count in Python and, for 8×8 with 8 queens
and 10×10 with 10, with the known 92 and 724. It refused `-n 27`,
`-n 5 -k 6`, a count of 0, and an argument after the count, each with
the usage message and status 2. The sample output below is that run's.

**Running it.** `queens [-n size] [-k queens] [all | count]`:

- `queens` asks after each solution whether to go on. Return or `y`
  goes on; `n`, or the end of the input, stops.
- `queens 5` prints the first five solutions (any count from 1).
- `queens all` prints them all.
- `-n` gives the board's size (8 if not given), `-k` the number of
  queens (the size if not given).

For each solution it prints the queens' squares in chess notation, then
the board drawn with `+`, `-` and `|`, with a `Q` on each queen's square
and the last rank at the top. When the solutions run out it says how
many there were.

**The search** is the recursive backtracking of Wirth's *Algorithms and
Data Structures*, with two changes:

- **A row may be left empty**, as long as enough rows remain for the
  queens still to place (`n - row >= k - placed`). That test is what
  keeps the search from wasting most of its time when `k` is small.
  When `k = n`, it is true only where every row so far has a queen, so
  the search then does exactly what the eight-queens search does.
- **Each solution is handed to the main program** with `Transfer`, and
  the search carries on from there when the main program asks for the
  next. That puts the main program in control: it can stop after any
  solution, or wait for an answer between two of them, without the
  search knowing why.

```oberon
MODULE Queens;  (* k queens on an n x n board, one solution at a time *)

  IMPORT Coroutines, Args, In, Out;

  CONST
    maxSize = 26;   (* files a to z *)
    (* modes *)
    askEachTime = 0; firstCount = 1; everySolution = 2;

  VAR
    main, solver: Coroutines.Coroutine;
    n, k: INTEGER;   (* the board's size and the number of queens *)
    column: ARRAY maxSize OF INTEGER;   (* row r's queen's column, -1 if none *)
    columnTaken: ARRAY maxSize OF BOOLEAN;
    upTaken, downTaken: ARRAY 2 * maxSize - 1 OF BOOLEAN;   (* the diagonals *)
    found: BOOLEAN;   (* TRUE: column holds a solution; FALSE: no more *)
    mode: INTEGER;
    count, limit: LONGINT;
    going: BOOLEAN;
    answer: ARRAY 80 OF CHAR;

  (* Wirth's backtracking search, with two changes: a row may be left
     empty while enough rows remain for the queens still to place, and
     each solution is handed to main instead of printed. A row not yet
     given a queen has column -1, and every path puts that back. *)
  PROCEDURE Place(row, placed: INTEGER);
    VAR c: INTEGER;
  BEGIN
    IF placed = k THEN
      found := TRUE; Coroutines.Transfer(solver, main)
    ELSIF n - row >= k - placed THEN
      FOR c := 0 TO n - 1 DO
        IF ~columnTaken[c] & ~upTaken[row + c] & ~downTaken[row - c + n - 1] THEN
          column[row] := c;
          columnTaken[c] := TRUE; upTaken[row + c] := TRUE;
          downTaken[row - c + n - 1] := TRUE;
          Place(row + 1, placed + 1);
          columnTaken[c] := FALSE; upTaken[row + c] := FALSE;
          downTaken[row - c + n - 1] := FALSE;
          column[row] := -1
        END
      END;
      Place(row + 1, placed)   (* and with this row empty *)
    END
  END Place;

  (* The solver's body. It must not return: after the last solution it
     answers every Transfer with "no more". *)
  PROCEDURE Solve;
    VAR r: INTEGER;
  BEGIN
    FOR r := 0 TO n - 1 DO column[r] := -1 END;
    Place(0, 0);
    found := FALSE;
    LOOP Coroutines.Transfer(solver, main) END
  END Solve;

  PROCEDURE NextSolution(): BOOLEAN;
  BEGIN
    Coroutines.Transfer(main, solver);
    RETURN found
  END NextSolution;

  PROCEDURE Rule;
    VAR c: INTEGER;
  BEGIN
    Out.Char("+");
    FOR c := 0 TO n - 1 DO Out.String("---+") END;
    Out.Ln
  END Rule;

  (* The solution's number, its queens' squares in chess notation, and
     the board, the last rank at the top. *)
  PROCEDURE Show(number: LONGINT);
    VAR r, c: INTEGER;
  BEGIN
    Out.String("Solution "); Out.Int(number, 0); Out.Char(":");
    FOR r := 0 TO n - 1 DO
      IF column[r] >= 0 THEN
        Out.Char(" "); Out.Char(CHR(ORD("a") + column[r])); Out.Int(r + 1, 0)
      END
    END;
    Out.Ln;
    FOR r := n - 1 TO 0 BY -1 DO
      Rule; Out.Char("|");
      FOR c := 0 TO n - 1 DO
        IF column[r] = c THEN Out.String(" Q |") ELSE Out.String("   |") END
      END;
      Out.Ln
    END;
    Rule
  END Show;

  PROCEDURE Usage;
  BEGIN
    Out.String("usage: queens [-n size] [-k queens] [all | count]"); Out.Ln;
    Out.String("size 1 to 26, 8 if not given; queens 1 to size, size if not given");
    Out.Ln;
    HALT(2)
  END Usage;

  PROCEDURE Upper(ch: CHAR): CHAR;
  BEGIN
    IF (ch >= "a") & (ch <= "z") THEN ch := CAP(ch) END;
    RETURN ch
  END Upper;

  (* Whether s is word, in either case: DCL passes an argument not in
     quotes in capitals. *)
  PROCEDURE Is(s, word: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (word[i] # 0X) & (Upper(s[i]) = Upper(word[i])) DO INC(i) END;
    RETURN (word[i] = 0X) & (s[i] = 0X)
  END Is;

  (* Argument i as a number from low to high, or the usage message *)
  PROCEDURE Number(i: INTEGER; low, high: LONGINT): LONGINT;
    VAR value: LONGINT;
  BEGIN
    value := low - 1; Args.GetInt(i, value);
    IF (value < low) OR (value > high) THEN Usage END;
    RETURN value
  END Number;

  PROCEDURE ReadArguments;
    VAR i: INTEGER; arg: ARRAY 32 OF CHAR;
  BEGIN
    n := 8; k := 0; mode := askEachTime;
    i := 1;
    WHILE i < Args.argc DO
      Args.Get(i, arg);
      IF Is(arg, "-n") & (i + 1 < Args.argc) THEN
        INC(i); n := SHORT(Number(i, 1, maxSize))
      ELSIF Is(arg, "-k") & (i + 1 < Args.argc) THEN
        INC(i); k := SHORT(Number(i, 1, maxSize))
      ELSIF mode # askEachTime THEN Usage
      ELSIF Is(arg, "all") THEN mode := everySolution
      ELSE mode := firstCount; limit := Number(i, 1, MAX(LONGINT))
      END;
      INC(i)
    END;
    IF k = 0 THEN k := n ELSIF k > n THEN Usage END
  END ReadArguments;

BEGIN
  ReadArguments;
  IF mode = askEachTime THEN In.Open END;
  Out.Int(k, 0); Out.String(" queen");
  IF k > 1 THEN Out.Char("s") END;
  Out.String(" on a "); Out.Int(n, 0); Out.Char("x");
  Out.Int(n, 0); Out.String(" board"); Out.Ln;
  (* The search is at most n + 1 calls of Place deep, below Solve: a
     small stack is plenty. *)
  Coroutines.Init(Solve, 16384, solver);
  count := 0; going := TRUE;
  WHILE going & NextSolution() DO
    INC(count); Show(count);
    CASE mode OF
    | askEachTime:
        Out.String("Another? [Y/n] "); Out.Flush;
        In.Line(answer);
        going := In.Done & (Upper(answer[0]) # "N")
    | firstCount:
        going := count < limit
    | everySolution:
    END
  END;
  IF going THEN
    Out.String("No more: "); Out.Int(count, 0); Out.String(" solutions in all.");
    Out.Ln
  END
END Queens.
```

`queens -n 5 -k 3 2` prints:

```
3 queens on a 5x5 board
Solution 1: a1 c2 e3
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   |   |   |   | Q |
+---+---+---+---+---+
|   |   | Q |   |   |
+---+---+---+---+---+
| Q |   |   |   |   |
+---+---+---+---+---+
Solution 2: a1 c2 b4
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   | Q |   |   |   |
+---+---+---+---+---+
|   |   |   |   |   |
+---+---+---+---+---+
|   |   | Q |   |   |
+---+---+---+---+---+
| Q |   |   |   |   |
+---+---+---+---+---+
```

**How many solutions.** These are the counts the variant found:

| board | k | solutions | calls of `Place` (Python's count) |
|---|---|---|---|
| 5×5 | 3 | 204 | |
| 8×8 | 1 | 64 | 73 |
| 8×8 | 2 | 1,288 | 1,576 |
| 8×8 | 3 | 10,320 | 13,987 |
| 8×8 | 4 | 34,568 | 55,012 |
| 8×8 | 5 | 46,736 | 97,259 |
| 8×8 | 6 | 22,708 | 76,386 |
| 8×8 | 7 | 3,192 | 26,611 |
| 8×8 | 8 | 92 | 4,022 |
| 10×10 | 5 | 1,535,440 | 2.3 million |
| 10×10 | 10 | 724 | 70,354 |
| 12×12 | 6 | 84,871,680 (Python only) | 121 million |

The count peaks near `k = n / 2` and falls to the n-queens count at
`k = n`. Python took 26 seconds just to count the 12×12 case. Printing
85 million boards is not a program anyone runs, so for `k` well below
`n`, asking after each solution or asking for the first few is the
normal way to use it.

**Why a coroutine here.** There are two other ways to write it, each
worse in one respect:

- **A callback.** `Place` could call a procedure for each solution, as
  Wirth's prints. Then the search is in control. Stopping early means a
  flag that every level of the recursion tests, and the code that talks
  to the user is turned inside out: what the main program does in a
  loop has to be done one call at a time, with its state kept in
  globals.
- **An iterative search.** It would not be hard here, since `column`
  already holds the search's state and a loop can back up through it.
  For a search whose recursion carries more state it is real work. The
  coroutine keeps the textbook's recursive procedure as it is.

Generalizing from eight queens to `k` on `n`×`n` changed `Place`, the
arrays and the argument parsing. `Solve`, `NextSolution` and the main
loop did not change, which is the point: the search can grow without
touching how the main program asks for results and pauses between
them.

Where 8.5's WordSets runs two coroutines in step, this program has one
generator and a consumer that talks to the user.

**Why it runs unchanged on Unix and VMS:**

- **Only portable modules.** It uses only `Args`, `In` and `Out`, the
  same interface in `rtl/llvm` and `rtl/vax`.
- **The prompt.** On VMS, `Out` keeps a line until `Ln`. `In` writes
  the unfinished line as the prompt for the next record it reads
  (`rtl/vax/In.Mod`), so `Another? [Y/n] ` appears before the input,
  where a user expects it. `Out.Flush` writes it to a terminal on VMS
  and does nothing on Unix, where `Out` keeps nothing. The end of the
  input (Ctrl-D on Unix, Ctrl-Z on VMS) makes `In.Done` FALSE, which
  stops the program.
- **Arguments in any case.** DCL passes an argument that is not in
  quotes in capitals, so `Is` ignores case: `-N 10 -K 5 ALL` works.
  `Upper` changes only letters, since what `CAP` does to other
  characters is not defined.
- **Running it on VMS.** It runs as a foreign command, as WordSets
  does: `QUEENS :== $DEV:[DIR]QUEENS.EXE`, then `QUEENS`, `QUEENS 5`,
  `QUEENS ALL` or `QUEENS -N 10 -K 5 3`.

**How it follows 8.4's rules [inferred]:**

- **I/O stays on the main stack.** The solver only searches. The
  prompt, the reads and the boards all happen in the main program.
  Waiting for the user's answer blocks the whole program (8.4, item 1),
  which is what this program wants, since there is nothing else to do
  while it waits.
- **Shared state without locks.** The main program reads `column` and
  `found` while the solver is suspended inside `Place`. That is safe
  because only `Transfer` switches: the solver cannot change `column`
  while `Show` is reading it.
- **The body never returns.** After the last solution, `Solve` answers
  every `Transfer` with `found` FALSE.
- **A stack abandoned mid-search.** When the user answers `n`, or a
  count is reached, the solver is left suspended inside `Place` for
  good. With `k` well below `n` that is the usual ending, not the
  exception. Oakwood has no `Free` (8.3, item 3), so the stack, and
  whatever it points to, stays until the program ends. Here that is
  harmless, because the program ends at once. In a program that keeps
  running, every search given up on is a stack kept. That is the case
  for 8.3's `Free`, or for a collected descriptor, and the strongest
  argument this example makes.
- **The stack size is small and known.** The recursion is always
  `n + 1` calls of `Place` deep, since an empty row recurses too: at
  most 27, below `Solve` and the trampoline, with one local each. 16384
  bytes is far more than enough on every target, the VAX's `CALLS`
  frames included.
- **The count.** `count` is a `LONGINT`, 32 bits under `-O2`. Only a
  search that finds more than 2^31 solutions would overflow it, and no
  one waits for that.

## 9. Option C: one possible interface

Added 2026-11-13, at the user's request: one possible exported
interface for option C's `Tasks` module, as a starting point if C is
ever taken up. Nothing here is decided, built or measured; all of it
is **[inferred]**.

### 9.1 The interface

```oberon
DEFINITION Tasks;  (* cooperative tasks over Coroutines; one OS thread *)

  CONST defaultStackSize = 65536;

  (* Tasks.  The body is a type-bound procedure of a heap object: Go's
     go f(x) without closures.  The extension's fields are its arguments
     and results. *)
  TYPE
    Task = POINTER TO TaskDesc;
    TaskDesc = RECORD END;

  PROCEDURE (t: Task) Run;      (* abstract: the body; returning ends it *)
  PROCEDURE Start (t: Task; stackSize: LONGINT);
  PROCEDURE Current (): Task;   (* the main program is a task too *)
  PROCEDURE Yield;
  PROCEDURE Join (t: Task);     (* until t's Run has returned *)
  PROCEDURE Done (t: Task): BOOLEAN;
  PROCEDURE Sleep (milliseconds: LONGINT);

  (* Conditions and locks.  A zeroed variable is ready to use (poc zeroes
     every variable), and they are passed by VAR, never copied. *)
  TYPE
    Condition = RECORD END;
    Mutex = RECORD END;

  PROCEDURE Wait (VAR c: Condition);       (* WHILE ~ok DO Wait(c) END *)
  PROCEDURE Signal (VAR c: Condition);
  PROCEDURE Broadcast (VAR c: Condition);
  PROCEDURE Lock (VAR m: Mutex);
  PROCEDURE Unlock (VAR m: Mutex);

  (* Channels.  Without generics a message is an extensible record,
     unpacked by a type guard. *)
  TYPE
    Message = POINTER TO MessageDesc;
    MessageDesc = RECORD END;
    Channel = POINTER TO ChannelDesc;
    ChannelDesc = RECORD END;

  PROCEDURE NewChannel (capacity: LONGINT): Channel;   (* 0: unbuffered *)
  PROCEDURE Send (ch: Channel; m: Message);
  PROCEDURE Receive (ch: Channel; VAR m: Message): BOOLEAN;  (* FALSE: closed and empty *)
  PROCEDURE TrySend (ch: Channel; m: Message): BOOLEAN;
  PROCEDURE TryReceive (ch: Channel; VAR m: Message): BOOLEAN;
  PROCEDURE Close (ch: Channel);
  PROCEDURE Select (VAR from: ARRAY OF Channel; VAR m: Message): LONGINT;
    (* receive from whichever channel is ready first; its index, or -1
       when all are closed *)

  (* Events: how asynchronous I/O wakes a task. *)
  TYPE Event = RECORD END;

  PROCEDURE Await (VAR e: Event);   (* block until posted, then reset *)
  PROCEDURE Post (VAR e: Event);    (* only sets a flag: safe in an AST or
                                       signal handler *)
END Tasks.
```

A task, as a program would write one:

```oberon
TYPE
  Worker = POINTER TO RECORD (Tasks.TaskDesc) n: LONGINT; out: Tasks.Channel END;
  Result = POINTER TO RECORD (Tasks.MessageDesc) value: LONGINT END;

PROCEDURE (w: Worker) Run;
  VAR r: Result;
BEGIN NEW(r); r.value := w.n * w.n; Tasks.Send(w.out, r)
END Run;
```

### 9.2 Why this shape

- **A body is a type-bound procedure of an extended `TaskDesc`**, not
  a procedure value with an argument. poc has no nested procedure
  values (section 5, finding 7), and an object is how Oberon-2 hands
  state to a body; Modula-3's `Thread.Closure` is the same idea.
  `Coroutines` still sees a global procedure: `Tasks`'s own
  trampoline, which calls `Current().Run`.
- **A task's stack can be freed when its `Run` returns.** That settles
  part of section 8.3, item 3, for tasks: the scheduler owns the
  trampoline, so it marks the task done, wakes any `Join`, and frees
  the stack at once. Only the descriptor lives on, for the collector
  to free. Returning is the normal end of a task, not trap 16.
- **Locks are rarely needed.** Nothing preempts, so code between two
  switch points is atomic already. `Mutex` is only for a region that
  contains a switch point (a `Send`, an `Await`, blocking I/O). Most
  programs need only `Condition`.
- **`Event` is the bridge to I/O.** A VMS `SYS$QIO` completion AST,
  or the scheduler's POSIX `poll` loop, calls `Post`; the waiting task
  is in `Await`. Allocation and switching stay out of handler context,
  as the AST and signal rule (section 5, finding 5; §22) requires.
- **The I/O wrappers are separate modules** (say `TaskFiles` and
  `TaskConsole`) over `Event`. Plain `In`, `Out` and `Files` still
  work, but a blocking call stops every task. On POSIX, `poll` calls a
  regular file always ready, so disk reads block anyway (Go uses extra
  threads for them); VMS's `$QIO` is asynchronous for disk files too.

### 9.3 Open questions

1. **When the program ends:** when the main module's body ends, as in
   Go (`Join` to wait), or only once every task has ended, as Ada's
   master rule does.
2. **Deadlock:** when every task is blocked and none waits on a timer
   or I/O, trap with a message and a new status, as Go's "all
   goroutines are asleep" does.
3. **Messages as extensible records** cost an allocation each, and the
   wrong type fails at the receiver's type guard. The alternative is
   typed channel modules for the basic types (`IntChannel` and so on).
4. **`Select`:** whether it covers sending too, and whether it takes a
   timeout. Go's full `select` with only procedures gets awkward fast.
5. **Cancellation:** Modula-3's `Alert`/`TestAlert` (a flag the
   blocking calls check), or none at first.
6. **Mixing with `Coroutines`:** whether a program that uses `Tasks`
   may still `Transfer` itself, and if so only to coroutines `Tasks`
   does not own.
