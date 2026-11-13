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
a proposal. **Nothing here changes poc.**

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
   VAX it is especially simple:
   - call a `Transfer` routine whose entry mask saves R2-R11;
   - store SP, FP and AP;
   - load the other coroutine's SP, FP and AP;
   - `RET`.

   The new stack's first frame must end the FP chain that VMS condition
   handling and traceback walk. That is still to be designed.

## 6. Options and proposal

| | Option | What a program gets | Cost to poc | Both back ends? |
|---|---|---|---|---|
| A | **Leave concurrency out** (status quo, documented) | Nothing new. The guides say threads are unsupported, and why (section 4.3). | One paragraph in `language-extensions.md` and the Reference Guide. A rule for signal and AST handlers. | yes |
| B | **Coroutines library** (Oakwood §1.2.8 interface, maybe with ISO Modula-2's names for the extras) | Explicit `Transfer` between coroutines with fixed stacks. A cooperative scheduler, generators and pipelines can be written in Oberon on top of it. | A runtime module and one context-switch routine per architecture (four). The collector scans a list of suspended stacks, empty unless the module is used. Stacks get guard pages (`mmap` with `MAP_STACK` on OpenBSD; on VMS, pages from `$EXPREG` with a protected guard page; **neither verified yet**). No compiler change. | yes |
| C | **B plus a cooperative task library**: `Tasks` with spawn, yield, join, monitors/conditions and channels, written in Oberon over B. Blocking I/O wrapped as DEC Ada's `TASKING_SERVICES` does: asynchronous `SYS$QIO` plus an AST that wakes the task; `poll` on POSIX. | Go-like structure without parallelism or preemption. Atomicity between switch points is guaranteed. | B, plus the library, plus wrappers around `Files`, `In` and the console for each OS. No compiler change. | yes |
| D | **Language-level tasks and monitors** (`EXCLUSIVE`/`AWAIT` à la Active Oberon, or protected types à la Ada) | Checked structure: shared data reachable only through the monitor's operations. | A Phase-sized extension: syntax, checker, `.sym`, both code generators, a shared-variable rule in `language-extensions.md`, `-strict` rejecting it. It needs C's runtime underneath. | yes, if built on C |
| E | **Preemptive OS threads** (POSIX threads; DECthreads on VMS) | Real parallelism on the LLVM targets, but not on the VAX (DECthreads there is single-processor). | Stop-the-world, scanning of every thread's stack, a heap lock, a reentrant runtime library, finalizers on their own thread, a memory model, and a draft-4 vs. final pthread shim on VMS. Effectively a new runtime. | in name only |

**Proposal [inferred]:**

1. **Now, whatever else is decided: option A's documentation.**
   - Say that poc's programs may not create threads, and why.
   - Give signal handlers (`Platform.SetInterruptHandler`) the AST rule
     of §22: no `NEW`, no `Out`/`Err`/`In`/`Files`.

   This fixes a gap that exists today.
2. **If the user wants concurrency at all: option B as a runtime
   module**, through `PLAN.md`'s "Ongoing library enhancements".
   - It is the step the Oberon tradition itself standardized.
   - It costs nothing for a program that does not import it.
   - It needs no change to the language or the checker, and it runs the
     same on every target, the VAX included.

   Its open design points are:
   - the stack size and guard pages on each OS;
   - what a returning body does (trap, as Oakwood forbids it);
   - the FP-chain terminator on VMS;
   - whether the collector's stack list belongs in
     `GarbageCollectedHeap` or in the new module.
3. **Option C is the natural next step after B** and can wait until
   programs ask for it. It too is a library, not a language change.
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
- OpenBSD's `MAP_STACK` requirement for any stack a thread runs on is
  from memory. Verify it against `mmap(2)` on cymoril before option B.
- How a VMS coroutine stack should be allocated and protected
  (`$EXPREG`/`$CRETVA` with `$SETPRT`) must come from the 5.5-2 System
  Services manual, as the project rule requires.
- The cause of the segfault in section 4.3 was not isolated. It does not
  matter for the proposal, because both candidate causes are present.
