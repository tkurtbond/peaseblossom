# Coroutines

A plan for option B of `doc/research/concurrency-survey.md`: a runtime
module `Coroutines` with the Oakwood Guidelines' interface (§1.2.8), on
both back ends, with no change to the language or the compiler. Its entry
in `PLAN.md` is "Ongoing library enhancements", 4, and it answers part of
Phase 19's candidate 7. The user accepted the decisions below as
proposed on 2026-11-13.

The survey's section 8 is the evidence. It describes a prototype that ran
on atla, the five BSD hosts and the SIMH VAX, and it is not repeated here.
Section 8.3 says what implementing B needs, and section 8.4 covers I/O and
C libraries, with five items "to settle before B's plan". Each of those
five is a decision below or a phase of the plan. The code was read at
`6ec47c1`.

## What is there now

- **No module.** The prototype was built in a scratch directory and is not
  in the tree. voc has no `Coroutines` either, so there is no twin for
  `rtl/voc` to keep. poc's own source will not use the module.
- **The collector scans one stack.** Each `GarbageCollectedHeap` marks from
  the current SP up to `stackBase`, which `main` records through
  `SetStackBase*`. That procedure is exported on both back ends
  (`rtl/llvm/GarbageCollectedHeap.Mod` and `rtl/vax/GarbageCollectedHeap.Mod`).
  The prototype showed what goes wrong without a hook (8.3, item 1):
  - the scan crashes;
  - or, worse, it loses objects silently: "1 wrong, 9999 missing".
- **Runtime parts in other languages.**
  - On LLVM, a module's `<M>.c` is compiled and linked with it, and
    `GNUmakefile`'s wildcard picks it up.
  - A VAX library can carry hand-written `.mar` parts (`part <name>` in its
    manifest, `src/driver/Libraries.Mod`). But `VAX_RTL_SRCS` names
    `rtl/vax/PocRtl.mar` explicitly, and so do `tools/bootstrap/make-vax-kit`
    and `tools/vax-guest-poc`.
- **Trap statuses 2-15 are taken.** 15 is the VAX's alone.
  - On the VAX, `POC_TRAP` maps any code above 15 to the text "trap". Slots
    16 and 17 of its table hold CHR's and VAL's texts, which code 14
    selects by its high word.
  - The VAX's runtime modules trap through `POC_TRAP`, as
    `GarbageCollectedHeap`'s `Trap` does.
  - On LLVM the code generator writes a trap inline. So a runtime module's
    trap belongs in its C part: the message to the standard error, then
    `exit(code)`. `atexit` runs the finalizers, as it does for a trap.

## Interface

```oberon
DEFINITION Coroutines;
  CONST
    DefaultStackSize = ...;   (* decision 4: not in Oakwood *)
  TYPE
    Coroutine = RECORD END;
    Body = PROCEDURE;
  PROCEDURE Init (body: Body; stackSize: LONGINT; VAR cor: Coroutine);
  PROCEDURE Transfer (VAR from, to: Coroutine);
  PROCEDURE Free (VAR cor: Coroutine);   (* decision 2: not in Oakwood *)
END Coroutines.
```

Oakwood's text, which these keep:
- "Init(p, s, c) creates and initialises a new coroutine c with a stack of
  s bytes and a body provided as the procedure p."
- "Procedure p must never return."
- "Transfer(f, t) transfers control from the currently executing coroutine
  to the coroutine t. The state of the currently executing coroutine is
  saved in f."

## Decisions

1. **A `Coroutine` holds one hidden field: a traced pointer to a
   descriptor** (8.3, item 2). The descriptor holds:
   - the saved SP (on the VAX, the saved FP);
   - the stack's low and high ends;
   - its state: new, suspended, running or freed.

   Records can be copied, so every copy names the same descriptor.
   - `Transfer(from, to)` stores the running coroutine's descriptor in
     `from`.
   - `main`'s descriptor is made by the first `Transfer` out of it, and it
     has no stack of its own to free.
   - `Transfer` to the running coroutine changes nothing.

2. **An explicit `Free`, with a misuse trap** (8.3, item 3).
   - `Free(cor)` gives back the stack and marks the descriptor freed. The
     descriptor itself stays, as long as any record names it. So a later
     `Transfer` to any copy of `cor` traps (17), rather than running on
     freed memory, and checking costs one comparison.
   - Freeing the running coroutine or `main`'s traps (17).
   - `Free` of a record never initialized, or of a coroutine already freed
     (through any copy), does nothing (decided with the user 2026-11-13).
     Copies are routine, so freeing one coroutine through two records is
     easy and harmless, and cleanup code need not know whether `Init` ran.
   - A coroutine that is never freed keeps its stack, and the collector
     keeps scanning that stack, until the program ends. That is the
     price of the explicit way, and the documentation says so.
   - The other way, a collected descriptor, needs a mark-time hook per
     object in the heap. It also has to deal with a stack whose C frames
     never finish (8.4, item 4(b)). It can be added later without
     changing the interface: `Free` would stay, as an early release.

3. **Trap statuses 16-18:**

   | Status | When | Text | VAX status |
   |---|---|---|---|
   | 16 | A body returned | `coroutine body returned` | `%X10000082` |
   | 17 | `Transfer` to a record never initialized, or to a freed coroutine; `Free` of the running coroutine or `main`'s; `Transfer` in a signal handler, an AST or a finalizer (decision 7) | one text for each case, as 14 has for `SHORT`, `CHR` and `VAL` | `%X1000008A` |
   | 18 | `Init` cannot get memory for the stack | `no memory for a coroutine's stack` | `%X10000092` |

   - Status 18 traps always, unlike `NEW`. A failed `NEW` leaves a NIL
     the program can test, but Oakwood's `Init` has no result to test.
   - These traps carry no location under `-trap-location`, since they
     come from the runtime and not from generated code. The table in
     `language-extensions.md` says so.

4. **Stack size.**
   - `Init` rounds `stackSize` up to whole pages and adds one guard page
     below, which is not counted in the size.
   - A size below a floor is raised to the floor. The floor leaves room
     for a signal handler (LLVM) or an AST (VMS), which run on whichever
     stack is current (8.3, item 8).
   - `DefaultStackSize` is a recommendation, not a default `Init` applies:
     Oakwood's `Init` always takes a size.
   - **The values**, to be confirmed by Phase 1:

     | | Floor | `DefaultStackSize` |
     |---|---|---|
     | LLVM | 16 KiB | 256 KiB |
     | VAX | 8 KiB | 32 KiB |

     On LLVM only the touched pages cost memory (8.2). On VMS,
     `LIB$GET_VM_PAGE` charges the page-file quota for the whole stack
     (8.4, item 4). The pofltk probe's high-water mark (Phase 1.1) decides
     whether 256 KiB is enough for a coroutine that calls FLTK.
   - A larger guard area against stack clash (8.4, item 3) is not
     proposed. The User's Guide's rule takes its place: put C with large
     frames on a large stack, or on `main`'s.

5. **The list of stacks lives in `Coroutines`. The heap gets a generic
   hook** (survey section 6, item 2; 8.3, item 1). Each
   `GarbageCollectedHeap` exports the prototype's three procedures:
   - `MarkRange(low, high)`;
   - `StackBase()`;
   - `SetStackScanner(p)`.

   It calls `IF stackScanner # NIL THEN stackScanner END` after
   `MarkFromStack`. `Transfer` moves `stackBase` to the coroutine it
   resumes. The scanner marks every suspended stack from its saved SP
   (or FP) to its top, and that includes `main`'s while a coroutine
   runs.
   - A program that does not import `Coroutines` pays one NIL test per
     collection (8.2).
   - The heap does not learn about stacks, and `Free` stays in the
     module, which is enough with decision 2.
   - The three exports are documented as being for `Coroutines`. Calling
     `MarkRange` on anything else is undefined.

6. **The context switch.**
   - **It saves the floating-point control registers**: MXCSR and the x87
     control word on x86, FPCR on arm64. That costs 2-3 ns of a 21-22 ns
     round trip, and it keeps a C part's rounding mode or exception masks
     with the coroutine that set them, as `swapcontext` does. The VAX has
     no such register; `RET` restores the PSW.
   - **The VAX's first frame is chained to `main`'s FP** (8.3, item 7), so
     the normal traceback lists a coroutine's frames. The `$UNWIND`
     hazard that comes with this is documented (decision 8).
   - **`MAP_STACK` is used on OpenBSD**, which requires it (8.3, item 5).
     It is not used elsewhere. FreeBSD gives the flag a meaning of its
     own, a region that grows down, which `Coroutines` does not want. The
     prototype ran on NetBSD and FreeBSD without it.
   - **LLVM: one C part, `rtl/llvm/Coroutines.c`.** Its switch is top-level
     assembly for x86-64, i386 and arm64, and any other architecture is
     an `#error`. i386 keeps 16-byte stack alignment at the first frame.
   - **VAX: a separate part, `rtl/vax/CoroutineSwitch.mar`** (the name is
     open), not more of `PocRtl.mar`. An object library links only the
     object modules a program references, so only the programs that
     import `Coroutines` get it. The kits, though, then assemble two
     `.mar` files on the guest, not one.

7. **Misuse that is cheap to catch traps (17). The rest is documented.**
   This follows the "cost only for users" rule: a documented rule, plus a
   cheap trap where one exists.
   - **A finalizer.** The heap already knows when it runs one, so a flag
     test in `Transfer` catches it.
   - **A signal handler (LLVM).** `PlatformSetHandler` installs the
     program's procedure directly. A wrapper in `Platform.c` that sets a
     flag around the call would catch it, at the cost of one store per
     signal. This is proposed.
   - **An AST (VAX).** `LIB$AST_IN_PROG` tells, but it is a call on every
     `Transfer`. So it is made only in a program that can have ASTs
     (`ExpectAsts` called, that is, one that imports
     `AsynchronousTraps`).
   - **The VAX's ASTs and the switch.** In a program that imports
     `AsynchronousTraps`, an AST may call `NEW`. One that comes between
     the move of `stackBase` and the switch of the stack would collect
     with the two out of step, and lose objects silently. So in such a
     program `Transfer` disables ASTs around the switch, through the
     heap's `EnterHeap`/`LeaveHeap` or the same `$SETAST`. Other
     programs pay nothing.

     On LLVM a signal handler may not call `NEW` ("Threads and signal
     handlers"), so the same window needs no guard there.

8. **8.4's rules, documented in `language-extensions.md`, "Threads and
   signal handlers", in the User's Guide and in the VAX/VMS Guide:**
   - A blocking call stops every coroutine. B has no I/O wrappers; they
     are option C's job (8.4, items 1 and 6).
   - No `Transfer` in a signal handler, an AST or a finalizer. Decision 7
     catches each where it is cheap.
   - Switching out of a C callback is allowed, but the coroutine must be
     resumed, and must return to C, before anything else uses that
     library (8.4, item 4). Pattern (a), where the library owns the main
     stack and its callbacks resume coroutines, is the one the guide
     shows.
   - Bodies never return. Stacks are fixed in size and do not grow.
   - **What ends a program on a coroutine:**
     - a stack overflow ends it with SIGSEGV on LLVM, and with an ACCVIO
       and two register dumps on the VAX;
     - no exception, `longjmp` or `$UNWIND` may cross a switch.
   - Shadow stacks (Intel CET, arm64's GCS and PAC) would break the
     switch. poc does not enable them today (8.3, item 9).

## What changes

| File | Change |
|---|---|
| `rtl/llvm/Coroutines.Mod` (new) | The interface. Descriptors and the list of suspended stacks. `Transfer`'s bookkeeping and `SetStackBase`. The scanner. The checks of decision 7 |
| `rtl/llvm/Coroutines.c` (new) | The switch and first frame for each architecture. The trampoline, which reports trap 16. `mmap` (plus `MAP_STACK` on OpenBSD), `mprotect` and `munmap`. The trap messages and `exit` for 17 and 18 |
| `rtl/vax/Coroutines.Mod` (new) | The same, with `LIB$GET_VM_PAGE`, `$SETPRT` and `LIB$FREE_VM_PAGE` through `["VMS"]` declarations. The protection is restored before the pages go back (8.3, item 3). Traps go through `POC_TRAP` |
| `rtl/vax/CoroutineSwitch.mar` (new) | The switch (`MOVL FP,@4(AP)`, `MOVL 8(AP),FP`, `RET`) and the fake `CALLS #0` first frame |
| `rtl/llvm/GarbageCollectedHeap.Mod`, `rtl/vax/GarbageCollectedHeap.Mod` | `MarkRange`, `StackBase`, `SetStackScanner` and the call (decision 5). A "finalizer running" flag `Coroutines` can read (decision 7). On the VAX, `MarkFromStack`'s caller `POC_SAVE_REGISTERS` is unchanged, since the scanner is called after it |
| `rtl/llvm/Platform.c` | The signal wrapper and its flag (decision 7) |
| `rtl/vax/PocRtl.mar` | Texts for 16-18, with 17's several texts selected by the high word, as 14's are. `POC_TRAP`'s range test and the table's slots for CHR and VAL move |
| `GNUmakefile` | `VAX_RTL_SRCS` gains the new `.mar` |
| `tools/bootstrap/make-vax-kit`, `tools/vax-guest-poc`, the kits' `.COM` files | The new part is carried and assembled |
| `packaging/` | The PLISTs (pkgsrc, OpenBSD and FreeBSD, for the main and VAX packages) list the module's files. The Fedora spec is checked for any list that does not glob |
| `doc/developer/language-extensions.md`, `AGENTS.md` | Rows 16-18 of "What traps, and what does not". The rules of decision 8 in "Threads and signal handlers", and its summary in `AGENTS.md` |
| `rtl/llvm/README.md`, `doc/reference-guide.md` | The module's entry. The runtime chapter is regenerated by `tools/rtl-reference update` |
| `doc/users-guide.md`, `doc/examples/` | A section on coroutines, with the survey's `WordSets` (8.5) and `Queens` (8.6) as its examples, checked by `tools/guide-examples` |
| `doc/vax-vms-guide.md` | Coroutines on VMS: the stack's quota, ASTs, the traceback, a stack overflow |
| `doc/research/concurrency-survey.md` | 8.5 and 8.6 no longer say the programs have not run. Section 6 records what was decided |

No compiler change (8.3, item 10).

## Plan

Each phase is checked on atla, cymoril, artos and alerik before it is
committed. The work is calls and memory layout, so rackhir runs after
Phases 3 and 4, and at the end. VAX phases run their fixtures on the
guest. New hand-written MACRO-32 goes to the user for review. The work is
done on the branch `coroutines`, and each phase is shown to the user and
committed only when the user asks.

### Phase 1: Probes

Before the decisions' values are final. Nothing is committed but the
survey's record of the results.

Done 2026-11-13; the results are in the survey's section 8.7. The values in
decision 4 stand, and the probes added to Phases 3 and 4: the trampoline's
unwind information, a fixture for it, a benchmark, and a traceback the VAX
fixture compares.

#### Phase 1.1: pofltk

8.4, item 5:
- Pattern (a): a script coroutine resumed by a button's callback.
- The main stack's high-water mark in a typical pofltk program, to size
  decision 4's `DefaultStackSize`.
- A nested `Fl.Wait` from a coroutine, to see whether pattern (b) is
  workable at all.

#### Phase 1.2: Debuggers

8.3, item 9: gdb's backtrace on a coroutine, on atla and one BSD, and VMS
DEBUG's `SHOW CALLS` on the guest. What a debugger can and cannot show
goes into the guides.

#### Phase 1.3: The VAX's quota

The floor and default against `POC`'s and `POC2`'s page-file quotas, and
how many default stacks fit.

### Phase 2: The decisions

Write the decisions, with Phase 1's values, into `language-extensions.md`
(the trap rows, the rules) and `AGENTS.md`'s summary, under the same
headings.

Done 2026-11-13: the trap table's rows 16-18 with 17's texts, two rows in
"What ends the program without a message", and a section "Coroutines" after
"Threads and signal handlers", in both files.

### Phase 3: The LLVM module

`Coroutines.Mod`, `Coroutines.c`, the heap's hook and `Platform.c`'s
wrapper, on x86-64, i386 and arm64. The trampoline's call-frame information
marks its return address undefined (`.cfi_undefined` `rip`, `eip` or `x30`),
so that gdb's backtrace ends there (survey 8.7.2). The fixtures each compare
their output (`. ../../testresult.sh`), and each has its `.gitignore` line:
- `llvm-coroutines`: the generator from `Ping`. A record copied before
  `Transfer`. `Transfer` to itself. `main` resumed by a coroutine that is
  not the one it last resumed;
- `llvm-coroutines-collector`: the prototype's `GcTest` in mode 2,
  shortened. Lists held only on suspended stacks survive many collections,
  at the default `-opt` and with `-lto`;
- `llvm-coroutines-free`: `Free`, then a new `Init` that reuses the
  memory; the misuse traps;
- `llvm-coroutines-traps`: 16; each case of 17; 18 under a `ulimit -v`; a
  NIL dereference (4), `HALT` and an `ASSERT` on a coroutine, each with its
  finalizers run;
- `llvm-coroutines-overflow`: a recursion into the guard page, giving
  SIGSEGV's status. The fixture accepts SIGBUS's status too, if a BSD
  gives that;
- `llvm-coroutines-c-callback`: a C part that calls back into Oberon, where
  the callback switches out and is resumed before it returns (decision 8's
  rule). A pointer held only in a C frame of a suspended stack survives a
  collection. The floating-point control word set in one coroutine is not
  seen in another (decision 6);
- `llvm-coroutines-unwind`: `readelf --debug-dump=frames` on
  `Coroutines.o` shows the trampoline's return register marked undefined,
  the fix for gdb's backtrace (survey 8.7.2), with no gdb needed.

`tools/bench/CoroutineBench.Mod`, beside `GcBench.mod`, is the prototype's
benchmark (survey 8.2) rewritten against the real module: a procedure-variable
call, `Transfer` there and back, `swapcontext` there and back, a collection
with 2 and with 10,002 stacks, shallow and deep, and `Init`'s cost. It is
run on atla and rackhir, and its figures are compared with 8.2's.

Done 2026-11-13 (`78574b8`); rackhir runs at the plan's end.

The figures (2026-11-14; rackhir's two runs, at `-opt 2`, with the stage 1
runtime; atla's collections from one run), against 8.2's for the
prototype. rackhir is emulated, so only its ratios mean anything:

| | rackhir, prototype | rackhir, module | atla, prototype | atla, module |
|---|---|---|---|---|
| Procedure-variable call | 28 ns | 24-25 ns | ~1 ns | |
| `Transfer` there and back | 410 ns | 294-295 ns | 21-22 ns | |
| `swapcontext` there and back | 8569 ns | 8116-8236 ns | 256-281 ns | |
| `Init` | ~27 µs | ~21.5 µs | ~2.5 µs | |
| First `Transfer` to a new stack | ~533 ns | ~650 ns | ~125 ns | |
| Collection, 100000 live, no other stacks | 8.2-9.4 ms | 8.5-8.8 ms | 1.20-1.32 ms | 1.10 ms |
| + 10000 shallow stacks | 14.8-15.5 ms | 18.3-19.1 ms | 1.81-1.85 ms | 1.79 ms |
| + 10000 stacks 100 frames deep | 111.8-111.9 ms | 232-236 ms | 8.04-8.09 ms | 10.83 ms |

The deep row is not the module's doing, or not most of it. The rewritten
`Deeper` takes its coroutine as a `VAR` record parameter, with its hidden
type tag, so a frame is 80 bytes on both machines where the prototype's was
49-50 (measured from the addresses of the deepest and shallowest frames'
locals; its array is 32 bytes, `LONGINT` being 4 under `-O2`): some 80 MB
scanned instead of 50. Taking the cost as so much a suspended stack plus so
much a byte scanned, atla's module matches the prototype (0.105 ns a byte
and about 45 ns a stack, against 0.126 ns and 41 ns). rackhir's is about
1.4 times the prototype's a byte (2.6 ns against 1.8) and twice a stack
(0.5 µs against 0.2), its stacks' bytes above `Deeper` estimated, not
measured. A collection with no other stacks costs what it did, so the
scan's code is not slower; whether FreeBSD arm64 puts the stacks inside the
heap's address range, so that a saved frame pointer costs a search of the
chunk table, or the emulator ran at another speed on the prototype's day,
was not settled: the prototype is gone.

### Phase 4: The VAX module

`Coroutines.Mod`, the `.mar` part, the heap's hook, `PocRtl.mar`'s texts,
`VAX_RTL_SRCS` and the kits. The trampoline is a routine of its own, so
that `SHOW CALLS` and the traceback name it on their last line (survey
8.7.2). The fixtures `vax-coroutines`, `vax-coroutines-collector`,
`vax-coroutines-free` and `vax-coroutines-traps` are run on the guest, along
with:
- the traceback of an access violation on a coroutine. The fixture
  compares the `%TRACE` listing: it must list the coroutine's routines down
  to its body and end at the trampoline's name. Leaving out the body, or
  printing no traceback at all, is what an unchained first frame does
  (survey 8.7.2);
- in a program that imports `AsynchronousTraps`, a timer AST that calls
  `NEW` while coroutines switch in a loop, for decision 7's window.

`make vax-stages` is not affected, since poc does not import the module.
The kits are checked by `tools/bootstrap/check-vax-kit`.

Done 2026-11-13 (`0298dbd`), with the traceback and AST cases as the
fixtures `vax-coroutines-traceback` and `vax-coroutines-asts`.

### Phase 5: Examples

`WordSets` and `Queens` go into `doc/examples/`, the User's Guide section
goes around them, and `tools/guide-examples update` is run. `Queens` is run
with fixed input, so the fixture compares its output. A VAX fixture,
`vax-coroutines-examples`, builds both programs from `doc/examples/` both
ways (MACRO-32 and objects) and runs them on the guest with the guide's
inputs, and `Queens` with other sizes too, expecting the same output as on
Unix: the run that shows the survey's "runs unchanged on Unix and VMS"
holds.

Done 2026-11-13 (`2631672`).

### Phase 6: Documents and packaging

`rtl/llvm/README.md`, `tools/rtl-reference update`, the VAX/VMS Guide, the
PLISTs, and `PLAN.md`'s entry marked `[done]`. The survey records what was
decided, and Phase 19's candidate 7 records B as adopted.

Done 2026-11-13. Writing the VAX/VMS Guide's section found that Phase 4's
`Transfer` called `LIB$AST_IN_PROG` in every program, not only in one
that imports `AsynchronousTraps` as decision 7 says; it now asks
`GarbageCollectedHeap.AstsExpected()` first.

Phases 3 and 4 can be released apart. The VAX's runtime simply lacks the
module until Phase 4, and a program that imports it gets poc's usual
"module not found".

Option C, a `Tasks` module over this one, is planned in
`doc/developer/tasks.md`, whose phases go on from 7.
