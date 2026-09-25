# Phase 10 — LLVM runtime library (voc-compatibility + Oakwood + Appendix C) + self-hosting

Moved here from `PLAN.md` unchanged on 2026-09-25, once the phase was done.
`PLAN.md` keeps the heading, the goal, and a list of the steps, so a reference
elsewhere to "`PLAN.md` Phase 10 step N" means step N here.

**Goal**: a real `rtl/llvm` module set, built as genuine Oberon-2 source
compiled by poc itself (not hand-written IR), covering (a) every voc
module poc's *own* front end/backend/driver source currently imports —
confirmed by grepping every `IMPORT` in `src/` for a non-`poc`-own
module name: `Out` (`Diagnostics.Mod`), and `Modules`, `Files`, `Out`,
`Platform` (`Poc.Mod`); `ModuleInterface.Mod`/`LLVMToolchainDriver.Mod`
also import `Files`/`Platform` — and (b) the Oakwood Guidelines' own
"basic" library modules (`In`, `Out`, `Files`, `Strings`, `Math`,
`MathL` — see below for `XYplane`/`Input`, the two basic modules this
phase deliberately excludes). Also covers (c) `SYSTEM` (Appendix C):
unlike (a)/(b), not a real `.mod` source file (`SYSTEM` has no body in
any Oberon-2 implementation — every procedure it exports is compiler
magic, the same way `PredeclaredProcedures.Mod`'s ordinary ~20 names
are), but grouped into this phase rather than Phase 13 because it's the
same kind of "give the LLVM backend a capability it has never had"
work as (a)/(b), and because `AGENTS.md`'s own "Appendix C" section has
flagged it as genuinely unscheduled ("no phase has scheduled it") since
before `PLAN.md` described any phase past 9 — see step 7 below. This
phase exists because Phase 9's own exit gate never needed real formatted
I/O, file access, or raw memory access — every Phase 8/9 fixture prints
via a direct `SysWrite` FFI declaration — but poc's own source genuinely
needs (a), and self-hosting (this phase's own final step) cannot get
off the ground without it.

**Why this is its own phase, not folded into Phase 9 or deferred to
"later, as fixtures need it"** (`PLAN.md`'s own "Decisions locked in"
table's original phrasing): the concrete list above came directly from
grepping poc's own source, at the user's explicit request, rather than
being assumed — and one real, load-bearing dependency fell out of doing
that for real rather than guessing: voc's own `Files.Mod` (confirmed by
reading `src/runtime/Files.Mod` in voc's own source tree) represents an
open file as `File* = POINTER TO FileDesc`, so even a from-scratch
`rtl/llvm/Files.Mod` needs real `POINTER`/`NEW`/GC to allocate one — Phase
9's own step 4/5 work, not something this phase can build around. Since
self-hosting additionally requires every *language* feature poc's own
source uses (which, being a fairly ordinary Oberon-2 compiler built
from heap-allocated, pointer-linked `Desc` records throughout
`SyntaxTree.Mod`/`SymbolTable.Mod`/`Types.Mod`, is effectively "most of
Phase 9"), self-hosting genuinely cannot happen before Phase 9's own
full-parity gate — hence this phase sitting immediately after it, with
its own bootstrap step as its capstone, not Phase 9's.

**Explicit non-goals**: `XYplane` (elementary pixel-plane graphics) and
`Input` (mouse/keyboard/clock access) are two of the Oakwood Guidelines'
own eight "basic" modules but presuppose a windowed/interactive
environment poc's own headless, batch, command-line target has no
equivalent of at all — voc itself only provides them under its
GUI-hosted `v4`/`oocX11` library personalities, never for the plain Unix
batch-compiler personality this project has followed since the
"Decisions locked in" table's own "Vishap Oberon, used two ways"
framing. `Coroutines`, `MathC`, `MathLC` are the Guidelines' own
"Additional Modules" — explicitly optional, "provided... on an 'as
needed' basis" — and nothing here needs non-preemptive threads or
`COMPLEX`/`LONGCOMPLEX` arithmetic (poc doesn't even support those as
types). `Texts.Mod`/`Oberon.Mod`/the interactive-environment modules
Appendix D itself describes (commands, dynamic loading, the browser) are
superseded here by the Oakwood Guidelines' own more portable `In`/`Out`
for the same reason the Guidelines exist in the first place — avoiding
baking in ETH Oberon System GUI-environment assumptions.

**Proposed build order** — each numbered step lands its own conformance
fixtures before the next starts, matching Phase 8/9's own incremental
style exactly. Every step here builds on Phase 9's `POINTER`/`NEW`/GC
work already being in place.

1. **`Console.Mod`.** `String(s: ARRAY OF CHAR)`/`Ln` (voc's own names, not
   the `PrintString`/`PrintLn` this step first proposed - so a program using
   them runs under both compilers), wrapping
   the same `write(2)` FFI call every Phase 8/9 fixture already declares
   inline, but as genuine Oberon-2 source compiled by poc and `IMPORT`ed
   by a small new fixture — proves the self-hosted-rtl-module mechanism
   for the first time (ordinary procedure-with-body codegen, Phase 8
   step 10, plus general multi-module `IMPORT`, Phase 8 step 12, working
   together on a *library* module, not just two peer user modules the
   way `llvm-multi-module` exercised it). Existing fixtures are not
   required to migrate off their own direct `SysWrite` declarations (low
   value, high busywork); new fixtures from step 2 onward should prefer
   `Console.Mod` where it's a natural fit. Not one of poc's own source
   dependencies (confirmed by the `IMPORT` grep above), but still built
   first: it's the smallest possible real rtl module, and every later
   step in this phase needs the same mechanism proven to work.
   **Testing**: one fixture (`llvm-console`, compile+link+run+diff-stdout)
   proving `Console.String`/`Console.Ln` end-to-end.
   **Implemented (2026-09-19)**: `rtl/llvm/Console.Mod` has voc's
   `Console` interface minus its input half - `Flush`, `Char`, `String`,
   `Int(i, n)`, `Ln`, `Bool`, `Hex` (`Read`/`ReadLine` belong to step 5's
   `In`). Decisions, probed against voc's `src/library/v4/Console.Mod`:
   - **Unbuffered**: voc line-buffers (128 characters, flushed at each
     newline) and, by its source, never flushes at exit, so output without
     a final `Ln` would be lost. Here every call writes before it returns, so nothing is lost
     to a trap or a plain end of program and it interleaves with other
     writers of descriptor 1; `Flush` is empty, kept for compatibility.
   - **One external `write(2)`**, declared `(descriptor: LONGINT; buffer,
     count: SYSTEM.ADDRESS)` with no result - the backend declares a C
     symbol once per program (first declaring module wins) and its trap
     support calls `write` as a `void` function, so a `Console` `write`
     returning a value would mismatch it. The price: a short write is not
     noticed. The count is `SYSTEM.ADDRESS`, `size_t`-wide, so it is right
     on i686 too (the older fixtures' `HUGEINT` count is passed as two words
     there, which works only because the low one comes first).
   - **`Int(i: HUGEINT; n: LONGINT)`** where voc's takes `SYSTEM.INT64`
     (poc has none yet; `HUGEINT` widens from every integer type). voc's
     goes through a `LONGINT`, so a value beyond it prints wrong (under
     `-O2`, `MAX(HUGEINT)` prints `1`) and it prints a fixed wrong string
     for the smallest one (read from its source, not run; its own "todo.
     support int64 properly"); poc's prints them right. The smallest `HUGEINT` is written whole,
     having no positive counterpart to print digit by digit. Padding is
     written as one write per 32 blanks, then the digits in one write.
   - **`Hex(i: LONGINT)`** prints two digits per byte of a `LONGINT`
     (8 under `-O2`), as voc's does.
   **Testing**: `llvm-console` (compile+link+run, and its output must equal
   what voc's own `Console` prints for the same source, checked in
   `test.sh` - voc runs first because poc leaves `Console.sym` in the
   working directory, which voc would find and reject); `llvm-console-extra`
   (poc only: `HUGEINT` beyond `LONGINT`, an unterminated `ARRAY OF CHAR`,
   and a program that imports `Console` while declaring `write` itself);
   both also run as i686 executables in `llvm-i686-runtime`. 176 pass.

2. **`Platform.Mod`.** The voc-only, non-Oakwood extension module poc's
   own driver depends on directly: `Chdir`/`CWD` (import-path/output-
   directory resolution), `GetEnv` (toolchain/environment lookup),
   `PID` (unique temp-file naming), `Unlink` (temp-file cleanup), and
   `System(cmd: ARRAY OF CHAR): INTEGER` — the exact mechanism a
   self-hosted `LLVMToolchainDriver.Mod` needs to shell out to `clang`/
   `llc` the same way it does today (voc's own real signature, confirmed
   by reading `src/runtime/Platformunix.Mod` in voc's own source tree).
   Every one of these is a thin wrapper over a `["C"]`-declared libc
   call (`chdir`, `getcwd`, `getenv`, `getpid`, `system`, `unlink`) —
   no allocation needed, the simplest step in this phase after
   `Console.Mod`.
   **Testing**: a fixture exercising `System` (run a trivial shell
   command, check its exit status) and `GetEnv`/`Unlink`/`Chdir`/`CWD`
   round-tripping a real environment variable and a real temp file.
   **Implemented (2026-09-19)**: `rtl/llvm/Platform.Mod` has exactly the
   six named above plus the `ErrorCode` type, with voc's own signatures
   (`Chdir(VAR n: ARRAY OF CHAR): ErrorCode`, `GetEnv(var: ARRAY OF CHAR;
   VAR val: ARRAY OF CHAR)`, `System(cmd: ARRAY OF CHAR): INTEGER`,
   `Unlink(VAR n): ErrorCode`, `PID-: INTEGER`, `CWD-: ARRAY 256 OF
   CHAR`) so poc's source compiles against either module. Not brought
   over: voc's file-handle, clock, signal and error-classification
   procedures - step 3's `Files.Mod` will add whatever it needs. Decisions,
   read from voc's `Platformunix.Mod`:
   - **An error is -1, not errno.** voc returns the errno value. The
     portable way to read it does not exist: `errno` is reached through
     `__errno_location` on Linux, `__error` on FreeBSD and `__errno` on
     NetBSD and OpenBSD, and an external declaration of a symbol the
     system lacks fails to link, with no conditional compilation to choose
     between them. Nothing in poc's source looks at more than `= 0`
     (the one place that mentions a code, `ModuleInterface.Write*`'s
     comment, only says what it happened to be). If a later module needs
     the reason, the fix is per-system - a small C shim, or a build-time
     choice - and belongs to Phase 11.
   - **`PID` is never negative.** voc keeps it in an `INTEGER`, so under
     its 16-bit `-O2` model a pid above 32767 wraps, possibly to a
     negative number, which `LLVMToolchainDriver.AppendInt` (documented as
     taking a non-negative number) would print wrongly. Here a pid that
     does not fit is reduced modulo 2^15 (one that fits is left whole,
     under a 32-bit `INTEGER` all of them).
   - **Strings must end in `0X` inside their array**: a `Chdir`, `Unlink`
     or `System` argument that does not is refused (-1) and a `GetEnv`
     name that does not finds nothing, instead of running `getenv`/`chdir`
     off the end of the array.
   - **`System` returns the raw wait status**, exit code times 256, as voc
     does, narrowed to `INTEGER` - `exit 255` (65280) wraps to -256,
     nonzero, which is all poc's own caller tests.
   - **C `int` is written `LONGINT`** in the external declarations, right
     under the `-O2` model poc generates code for, wrong under `-OC` (a
     64-bit `LONGINT` reads a return register's upper half, which the
     ABI leaves undefined). Step 7's `SYSTEM.INT32` is only an alias of
     `LONGINT` (the `-O2` width), so it is *not* the size-model-independent
     spelling this needed and the move was not made; step 8's self-hosting
     under the `-OC` model needs a real fixed-width `INT32` (Phase 11 table)
     and these declarations, and `Console`'s `write`, moved to it.
   **Testing**: `llvm-platform` (25 checks over `GetEnv` - a set, an empty,
   an unset and a truncated variable; `System`'s status; `Unlink` of a real
   file twice; `Chdir` into a real directory and back, seen from the
   shell a `System` call starts and from `CWD`, and a failing one - run
   under poc and voc, which must print the same; `test.sh` exports the
   variables and builds the directory, and, as for `Console`, runs voc first
   because poc leaves `Platform.sym` in the working directory); `llvm-platform-extra`
   (poc only: `PID` against the shell's own `$PPID`, `-1` as the failure
   code, unterminated strings), also run as an i686 executable in
   `llvm-i686-runtime` (`llvm-platform` needs its environment and
   directory, which that harness does not set up). 178 pass.

3. **`Files.Mod`.** The subset poc's own source actually calls (again
   confirmed by grep, not assumed): `File`, `Rider`, `New`, `Old`,
   `Register`, `Close`, `Length`, `Set`, `Write`, `WriteString`,
   `ReadLine`, `ReadString` — enough for `ModuleInterface.Mod` to read/
   write `.sym` files and `LLVMToolchainDriver.Mod` to read/write `.ll`
   files once self-hosted. `File* = POINTER TO FileDesc` (matching voc's
   own representation) is why this step comes after Phase 9's GC, not
   before it; the underlying bytes move through `["C"]`-declared
   `open`/`read`/`write`/`close`/`lseek`. This module happens to also be
   one of the Oakwood Guidelines' own eight "basic" modules, so building
   it against poc's own concrete usage automatically covers most of the
   Guidelines' own `Files` interface too, not just poc's narrower slice.
   **Testing**: a fixture that creates a file, writes through a
   `Rider`, closes it, reopens it, and reads the same bytes back via
   `ReadString`/`ReadLine`.
   **Implemented (2026-09-20)**: `rtl/llvm/Files.Mod` has the twelve
   procedures above plus `Read`, `Pos`, `Base`, `Delete` and `Rename`, with
   voc's signatures except that `Read`/`Write` take a `CHAR` where voc's
   take `SYSTEM.BYTE` (step 7). Not brought over: `ReadBytes`/`WriteBytes`
   (need `BYTE` too), the typed `ReadInt`/`WriteReal`/... family, `Purge`,
   `GetDate`, `GetName`, `SetSearchPath`. `File` is
   `POINTER TO FileDesc` as planned, so the module needs `NEW` and the
   collector. The Oakwood interface is therefore *not* mostly covered, as
   this step expected: what poc calls is a small slice, and the rest is
   Phase 11's if wanted. Decisions, read from voc's `Files.Mod`:
   - **stdio, not `open`/`lseek`, as planned.** The bytes move through
     `fopen`/`fread`/`fwrite`/`fseek`/`fclose`/`rename`. `open(2)` takes
     flag bits that differ between Linux and the BSDs (`O_CREAT` is 0x40 on
     Linux and 0x200 on the BSDs, `O_TRUNC` 0x200 and 0x400), and `lseek`'s
     `off_t` is 32 bits on 32-bit Linux and 64 on 32-bit NetBSD, OpenBSD
     and FreeBSD, so an external declaration right for one is wrong for
     another, and there is no conditional compilation to pick. stdio has a
     mode *string* and a `long` offset, a word on all of them. (The BSD
     values are from memory: to be confirmed on the BSD hosts.) The
     `i686` run of both fixtures below passes with the 32-bit `long`.
   - **No buffers of its own** - voc keeps four 4 KB buffers per file and
     a table of open files, to share them between `File`s of one OS file,
     and a `Deregister` that moves an open file out of the way; libc's
     buffering replaces the first and Unix's `rename` semantics the third.
     A `File` is a stream, a length and a position; a `Rider` is a
     position. The operations seek when the stream is somewhere else or was
     last used the other way.
   - **`New` writes to a temporary file** (`.tmp.<n>.<pid>` beside the
     final name, created at the first write) and `Register` renames it, so
     a registered file replaces the old one in one step and never appears
     half written; voc does the same once it has more than four buffers
     of data, and writes directly otherwise. Names are made absolute
     when given, so a `Chdir` between `New` and `Register` does no harm
     (by its source, voc renames its absolute temporary name onto the
     relative final one, i.e. into the wrong directory).
   - **`Close` closes the stream**, and the `File` reopens itself if used
     again. Nothing here finalizes a `File` (the collector has no
     finalizers), so this is what keeps a program from running out of
     descriptors; a dropped `File` still keeps its stream until the
     program ends.
   - **Failures**: `Old` gives `NIL` for a missing file, an empty or too
     long name, or a directory (which `fopen` accepts for reading on
     Linux; a one-byte probe read finds it). What cannot be reported - a
     file that cannot be created, a write that fails - prints
     `-- <what>: <name>` and stops with `Halt(99)`, as voc does.
   - **Where voc differs and poc does not follow**: two `Old` calls for one
     file give two independent `File`s (voc shares one); `ReadString`/
     `ReadLine` cut an over-long value short where voc overruns the array;
     files are limited to a `LONGINT`'s range (voc's too under `-O2`).
   - **voc quirks met while cross-checking**: `Rename` or `Delete` of a
     file that this process has open as a `File` makes voc rename it to a
     temporary name first, so, apparently, `Delete` fails (errcode 2)
     and `Rename` halts ("Couldn't rename previous version of file being
     registered"); the shared fixture only renames and deletes files it has not
     opened, and looks at the result with the shell.
   **Testing**: `llvm-files` (37 checks: a new file's length as it grows,
   register, reopen, `ReadString`, `ReadLine` over LF, CR LF, empty and
   unterminated lines, `Set` clamping, overwriting and extending, a
   20000-byte file probed at the 4096-byte block boundaries voc uses, two
   riders on one file, `Old` of nothing, registering over a file, use
   after `Close`, `Delete`/`Rename` - run under poc and voc, which must
   print the same); `llvm-files-extra` (19 checks, poc only: values cut
   short, the temporary file and where it lives, `Chdir` between `New`
   and `Register`, a directory and a 300-character name given to `Old`,
   2500 opens in a row with `Close`, failures being -1); `llvm-files-fail`
   (an uncreatable file: message and exit status 99). `llvm-files` and
   `llvm-files-extra` also run as i686 executables in `llvm-i686-runtime`.
   181 pass. **Checked against poc's own source**: `poc -emit-llvm-ir` of
   `ModuleInterface.Mod`, the heaviest user of `Files`/`Platform`, with the
   whole front end below it and a throwaway `Out` standing in for step
   5's, compiles against these two modules. `LLVMToolchainDriver.Mod` does
   not get that far, for a reason that has nothing to do with them:
   poc's checker rejects poc's own `SemanticActions.Mod` (29 x "guarded
   pointer variable may be manipulated by non-local operations", the
   `WITH` rule that `CheckWithGuard` applies more strictly than voc
   does).

   **Settled (2026-09-20, step 8): `CheckWithGuard` now matches voc's real
   rule exactly, not just more closely.** The 29 rejections were plain
   type-case dispatches in poc's own source (`WITH node: ...ArrayTypeNode
   DO`, `WITH sel: ...FieldSelector DO`, and the like) over an ordinary,
   non-`VAR` local - never genuinely reachable from another procedure by
   Oberon-2's own scoping rules, only flagged because `CollectProcAssigned
   Names`'s original whole-module pre-pass matched by bare name text with
   no notion of which procedure declared which variable, and `node`/`sel`/
   `s` are used constantly across this file. Probed voc directly (six
   standalone repros, `/tmp/vocwg/vocwg1..6.mod`) rather than trusting the
   header comment's own account from memory, and found voc's real rule is
   both simpler and more precise than what poc had approximated: a local
   may be reassigned by bare name *anywhere at all in its own declaring
   procedure*, including textually inside the very guarded branch (voc
   accepts that directly - no statement-order or reachability distinction
   is drawn within the declaring procedure itself); only a reassignment
   inside a procedure *nested inside* the declaring one (any depth) is
   rejected; an unrelated procedure's own same-named-but-different local
   never interacts at all (voc resolves by declared identity, never text).
   New `SymbolTable.ScopeDesc.enclosingProc` (set at every procedure's own
   body scope, top-level or nested, and carried through any scope opened
   another way - a `WITH`'s own narrowed scope) gives `CheckWithGuard` this
   distinction for free: a global still uses the whole-module scan
   (genuinely reachable from anywhere), a local uses a scan of just its
   declaring procedure's own *nested* procedures (never its own direct
   statements). Re-verified against all six voc repros: exact agreement.
   `SemanticActions.Mod` now checks clean under real `poc -check`.

   **Every front-end/backend/driver file checks clean under `poc -check
   -OC` (2026-09-20).** Pushing on past `SemanticActions.Mod` hit what
   looked like a second, genuine blocker: `LLVMCodeGenerator.DoubleBitsText`
   declares `mantissa: LONGINT` and assigns it `2251799813685248` (2^51,
   the quiet-NaN bit) - too wide for a 32-bit `LONGINT`, so poc's own
   minimal-integer-literal-type rule types the numeral `HUGEINT` and
   correctly rejects the assignment under poc's *default* `-O2` model.
   This turned out not to be missing functionality at all: `Poc.Mod`
   already has real `-O2`/`-OC` flags (`ConstantEvaluator.SetSizeModel*`,
   built in Phase 9 step 10 for `MAX`/`MIN`/`SIZE` constant folding) -
   this session's own self-check commands simply weren't passing `-OC`,
   the same flag `tools/bootstrap/stage0` already builds poc's own source
   with (its own header comment already says why: `Types.Value.intVal`
   needs a real 8-byte host `LONGINT` to hold a full-range `HUGEINT`
   constant). Re-running every front-end file, every `rtl/llvm` module
   poc's own source imports, both backend files and `src/driver/Poc.Mod`
   itself through `poc -check -OC` (not just `-emit-interface`, so every
   procedure body is checked, not just signatures) - all clean, zero
   errors. `Poc.Mod` compiling clean under its own checker is real
   evidence Stage 1 *type-checking* is unblocked.

   **A real `poc -build`/`-emit-llvm-ir` attempt on the whole program found
   two genuine codegen bugs, both the same class, both fixed (2026-09-20).**
   `poc -build src/driver/Poc.Mod` (whole program, `-OC`) crashed `poc`
   itself with an opaque `Terminated by Halt(-2). Index out of range.` -
   poc's own array-bounds check, working as designed, catching an
   out-of-bounds write rather than corrupting memory, but with no stack
   trace to say where. Isolated with temporary `Out.String` progress
   prints in `GenerateProcedureDecl` (rebuilt via Stage 0 after each
   change) plus bisection on scratch copies of the real source (neuter a
   suspect procedure's body down to nothing, confirm the crash disappears,
   restore statements one at a time) - the standard technique this session
   used earlier for the `WITH`-guard bug, reapplied here twice:
   - **`LLVMTypes.TypeString`'s recursive struct-type-string builder had no
     bounds check** against its `VAR result: ARRAY OF CHAR` destination -
     fine for every fixture built so far (all short, hand-written test
     programs), but poc's own `Parser` record (`src/front/Parser.Mod`) -
     an ordinary three-field record, nothing exotic - built a struct type
     string over 64 characters once nested, overflowing the 64-character
     `ValueText` buffer essentially every call site passed. Minimal repro:
     a `VAR` parameter of a record type containing a nested pointer-
     bearing sub-record, a plain non-pointer middle field, and a second
     direct pointer field, with a same-typed local declared - `/tmp/wgtest`
     and `/tmp/recbug`'s `rb4`..`rb12` narrowed this down live. Fixed: a
     new `LLVMTypes.typeStringLength*` (799, comfortably larger than any
     record type this project's own source produces - see its own header
     comment for the full account) replaces the internal 256-character
     buffers in `RecordTypeString`/`ArrayTypeString`, and `Value.llvmType`
     plus every other `LLVMCodeGenerator.Mod` local/field that receives an
     arbitrary (not hardcoded-basic) type's string - `EmitGlobals`,
     `BindLocalVars`, `BindFormalParams`, `ParamLLVMType`, pointer-
     dereference/guard/narrowing sites, function-result-type sites - moved
     from `ValueText` (64) to the existing `LongText` (800). Purely
     numeric-only sites (`GenerateDivMod`, relational ops, `SHORT`/`ASH`,
     `SET` operations, `CASE` label widening) were left alone: Appendix A
     restricts those operators to basic types, so a record type can never
     reach them - confirmed by reasoning about the report's own rules, not
     assumed.
   - **A second, different instance same class, found by pushing on past
     the first fix**: `GenerateNew`'s own `tagText: ValueText` wraps the
     already-`LongText`-sized `longTag` (a type's full `ptrtoint (ptr
     @Module.Type.tag to iN)` operand) in a second buffer sized like the
     first bug's - safe for any external test fixture's short module name,
     but `LLVMCodeGenerator.Mod` compiling *itself* embeds its own 18-
     character module name in every symbol it generates for its own
     types, pushing `NEW` of one of its own record types (`DeclaredExternal
     Desc`, found processing `MarkDeclaredExternal`) over 64 characters.
     Fixed the same way: `tagText` moved to `LongText`. `QualifiedName`/
     `ModuleQualifiedName` use the identical pattern but were checked and
     left alone - poc's own longest procedure name (`InitImportPath
     FromEnvironment`, 29 characters) plus its longest module name
     (`LLVMToolchainDriver`, 19) stays well under 64, confirmed by grepping
     every declared procedure name in the project, not assumed safe.
     `make test` (198) clean after each fix; both verified by re-running
     the exact triggering `-emit-llvm-ir` command on the real file.

   Past both fixes, `poc -build` on the whole program gets measurably
   further: `poc` itself no longer crashes, and `clang` now rejects the
   generated `Poc.ll` outright - `%t26751 = call ptr
   @SemanticActions.NewQualidentType([256 x i8] 0, [256 x i8] 0, i32
   %t26749, i32 %t26750)`, an integer literal `0` where an `[256 x i8]`
   array constant belongs.

   **A third bug, a real gap rather than a buffer size, found and fixed
   (2026-09-20): passing a string literal to a *value* `ARRAY OF CHAR`
   parameter (Oberon2.pdf Appendix A rule 3 - AGENTS.md's own language-
   spec notes) never had real codegen at all.** `EvaluateCallArg`'s plain
   (non-`VAR`, non-open-array) branch always routed through `GenerateExpr`/
   `GenerateLiteral`, whose own header comment already documented the
   invariant it silently violated here: "a string in a character-sequence
   position ... never comes through GenerateExpr at all" - true for
   assignment, COPY and comparisons, each with their own dedicated path,
   but never actually enforced for a call argument. An empty string hit
   `GenerateLiteral`'s own "empty string literal in a scalar position"
   placeholder (a bare `0`, meant for genuinely unsupported shapes);
   poc's own `Parser.Mod` calling `SemanticActions.NewQualidentType("", "",
   ...)` - two 256-character `SyntaxTree.Ident` value parameters - is the
   real repro. Fixed with a new `GenerateCallArgList`-level special case
   (`AppendStringLiteralArrayConstant`, `AppendChar`/`AppendEscapedByte`)
   that builds a real `[N x i8] c"..."` LLVM array constant directly -
   bypassing `EvaluateCallArg`/`Value` entirely, since the escaped text
   (the array's own unwritten tail zero-padded byte by byte, three
   characters per `\XX` escape) runs well past `Value.text`'s own
   `ValueText` bound for any real fixed array, and widening `Value.text`
   itself turned out far too invasive (17 existing `:=` assignment sites
   broke, reverted). A second problem surfaced immediately after fixing
   the first, live against poc's own source rather than a hand-written
   repro: `GenerateCallArgList`'s own accumulated `text` buffer (`LongText`,
   800 characters) comfortably holds *one* such constant (782 characters
   for a 256-length array) but not `NewQualidentType`'s own *two* in one
   call (~1564 characters together, before the trailing `INTEGER`
   arguments) - `AppendStringLiteralArrayConstant`'s own defensive bound
   check (against the room actually *left* in the buffer, not the buffer's
   total declared size - an earlier version of the check missed this and
   still passed every hand-written repro, which never happened to chain
   two such arguments in one call) correctly refused the second one and
   fell back to the old, still-broken path, which then overflowed the
   now-nearly-full 800-character buffer for real, tripping the exact same
   index-range trap as the first two bugs. Fixed with a new, dedicated
   `ArgsText` (4096 characters, comfortably holds several such arguments
   at once) replacing `LongText` for every `GenerateCallArgList`-facing
   `argsText`/`receiverText` variable - `AppendStringLiteralArrayConstant`
   itself needed no change, since its own bound check already reads the
   buffer's real size via `LEN(text)`. Both steps isolated the same way as
   the earlier two bugs: temporary `Out.String` progress prints (this time
   inside `EvaluateCallArg`/`AppendStringLiteralArrayConstant` themselves,
   not just `GenerateProcedureDecl`), rebuilt via Stage 0 and re-run
   against the real file each time, removed once each fix was confirmed.
   `make test` (198) clean throughout.

   **Stage 1 reached (2026-09-20): `poc -build src/driver/Poc.Mod`, using
   `poc` itself, produces a real, working executable.** `poc-stage1` runs
   (`poc-stage1 -check-syntax ...` succeeds against real source) - the
   first time poc has ever compiled itself into a working binary, not just
   type-checked its own source.

   **Stage 2 and the fixed point reached (2026-09-20).** `poc-stage1` first
   trapped at run time with "no matching WITH guard" (exit 6), on any
   module with a module-level `VAR`. `gdb -batch -ex 'break exit' -ex run
   -ex bt` on the Stage 1 binary named the procedure at once
   (`LLVMCodeGenerator.CollectRecordTypes`; the binary keeps its symbols) -
   quicker than the print-and-bisect method the three earlier bugs needed,
   since a poc-built program, unlike a voc-built one, is an ordinary native
   executable. The cause was not a logic gap in that procedure: its `WITH`
   ends in an explicit empty `ELSE END`, which parses to a NIL `elseBody`
   exactly like no `ELSE` at all, and `GenerateWithStatement` chose
   trap-versus-fall-through by `s.elseBody # NIL`. The same ambiguity had
   been fixed for `CASE` in Phase 8 (`hasElse`); `WITH` never got the
   flag. Fixed the same way: `WithStatementNodeDesc.hasElse`, set by
   `Parser.Mod`, passed through `SemanticActions.NewWithStatement`, tested
   by `GenerateWithStatement`. poc's own source is full of `ELSE END`
   `WITH`s (a `WITH` used only to pick out what to do next, falling through
   for any other node), so every one that fell through trapped, and no
   existing fixture had one. New fixture `llvm-with-empty-else` (fails
   without the fix, with the trap; 199 fixtures now).

   With that, Stage 2 builds, and a third generation from it too. The
   whole-program `Poc.ll` (3.6 MB), every generated `.sym` and the
   executable are byte for byte identical across Stage 1, Stage 2 and
   Stage 3 - nothing in them carries a timestamp or a path, so no "modulo"
   was needed. The full conformance suite passes under the Stage 1 binary
   (199/199, `POC_BIN_DIR` pointing at it) as it does under Stage 0's.
   `tools/bootstrap/stage1` and `stage2` (the latter does the comparison
   and exits non-zero on any difference), and `make stage1`/`make stage2`,
   are the scripts this step promised. `make test-stage1` runs the suite
   under the poc-built poc (`POC_BIN_DIR=build/stage1/bin`) and `make check`
   runs both suites and the Stage 2 comparison, whatever fails along the way;
   `make test` stays voc-built only, the fast loop - voc is still the only way
   to bootstrap and the oracle for the comparison.

   **BSD-verified (2026-09-20), and a real, NetBSD-only bug found and
   fixed along the way.** All 23 of Phase 10 steps 1-7's runnable rtl
   fixtures (`llvm-console` through `llvm-system-shifts`, the full list
   in "SYSTEM subset" and this step and steps 1/2/4-7's own "Testing"
   entries) were cross-compiled with `-target i386-unknown-openbsd7.9`/
   `-target x86_64-unknown-netbsd10.0`, copied to `erekose`/`terhali`
   (see "Vishap Oberon"/[[reference-bsd-test-hosts]]), and built+run there
   with each machine's own native `clang`, same method as Phase 8 step
   13's original sweep. First pass: 23/23 on erekose, 22/23 on terhali -
   `llvm-files-extra` check 14 (`Files.Old` of a directory name must be
   `NIL`) failed there. Root cause, confirmed with a standalone C probe
   run on both machines: `Old`'s directory rejection (the `Readable`
   procedure above) relies on a one-byte `fread` of an `fopen`'d directory
   failing - true on Linux and OpenBSD (`count=0`, `ferror=1`), but
   NetBSD's libc lets that `fread` succeed (`count=1`, `ferror=0`) - an
   old BSD allowance for reading raw bytes off a directory stream that
   Linux and OpenBSD's libc no longer honor, not a poc bug in the usual
   sense. Fixed with a new `IsDirectory` check ahead of the `fopen` path,
   using `opendir`/`closedir` instead of the `fread` probe - POSIX
   `opendir` succeeds only for a directory, confirmed identically on
   Linux, OpenBSD and NetBSD (no FreeBSD host to check against yet).
   `Readable` is kept as a second guard for whatever else might open but
   not read. Re-run after the fix: 23/23 on both erekose and terhali, and
   `make test` (198, unchanged) still clean on Linux. The O_CREAT/
   O_TRUNC/off_t values mentioned above remain unconfirmed on the BSDs -
   moot, since `Files.Mod` never calls `open`/`lseek` at all, only stdio.

   **Self-hosted poc on the BSDs (2026-09-20).** poc's own `Poc.ll` was
   cross-compiled here for `x86_64-unknown-netbsd10.0` and
   `i386-unknown-openbsd7.9`, copied over and built with each host's own
   `clang`. *NetBSD amd64*: the result runs, rebuilds poc there
   (`-OC -target x86_64-unknown-netbsd10.0 -build`), and emits a `Poc.ll`
   byte-identical to the Linux cross-compile - the fixed point holds across
   an OS. The conformance suite under that binary: **199/199** once the
   harness's own Linux assumptions were fixed, all found by this run and
   none a poc bug: (1) a program voc builds needs voc's shared runtime
   (`libvoc-O2.so`), which Linux finds by itself but NetBSD/OpenBSD do not,
   and which a non-interactive `ssh host cmd` gets only from the login
   profile's `LD_LIBRARY_PATH` - `testenv.sh` now sets it from the voc
   directory (`VOC_LIB_DIR`); (2) four `*-ir` fixtures normalized labels
   with `sed`'s GNU-only `\b` (BSD `sed`: "trailing backslash") - now an
   explicit boundary class, goldens unchanged; (3) `llvm-gc-roots-ir` used
   `grep 'a\|b'`, a GNU BRE extension OpenBSD's `grep` lacks - now `grep -E`;
   (4) `llvm-i686-runtime` builds for `i686-unknown-linux-gnu`, which cannot
   link on a BSD even one that runs 32-bit programs (NetBSD amd64 does) -
   it now builds for `i686_triple`: that triple on Linux, and on any other
   system the one `clang -m32 -dumpmachine` gives (`i386-unknown-netbsd10.0`
   on terhali, the host's own `i386-unknown-openbsd7.9` on erekose), so all
   three hosts run its 50 checks for real; (5) `llvm-system-shifts`
   compared poc with voc on `ROT(l, 0)`, which voc's C expands to a shift by
   the full width - undefined, and clang on i386 folds it differently from
   x86-64 (its own warning says so) - moved to `llvm-system-extra`, the
   poc-only fixture, so the voc-compared one has only cases voc defines.
   NetBSD's linker also warns that `Files.IsDirectory` references a
   *compatibility* `opendir()` (the symbol before NetBSD 3's `dirent`
   change; `dirent.h` renames it) - works, but should be declared the way
   the header does. *OpenBSD i386* also passes **199/199**, with a Stage 0
   poc built there by voc (`tools/bootstrap/stage0`, ILP32, `-OC`); the
   self-hosted one did not run at first, below - it does now, see "Fixed-width
   `SYSTEM.INT8..INT64`" after this.
   *OpenBSD i386*: the cross-built poc **built but did nothing** - every
   `write` fails (`ktrace`: `write(1, 0, <stack address>)`, EINVAL). Cause,
   from the IR: `declare void @write(i64, i32, i32)`. Under `-OC` `LONGINT`
   is 64 bits, and `rtl/llvm` declares its C `int` parameters and results
   (`Console`'s `write`, `Platform`, `Files`, `Out`'s `isatty`, `Math`) as
   `LONGINT`; on x86-64 the extra width is invisible (register arguments),
   on i386 the 64-bit `fd` takes two stack words and shifts the rest. So
   poc built with `-OC` - which it needs, for `Types.Value.intVal` - cannot
   run on a 32-bit target until the Phase 11 item "real fixed-width
   `SYSTEM.INT32` family, then move the C `int` declarations to it" is done;
   it is that item's first real customer (the small runtime fixtures still
   pass there, built under the default `-O2`, where `LONGINT` is 32 bits).
   Not fixed at that point; done next.

   **Fixed-width `SYSTEM.INT8..INT64`, and the self-hosted poc on 32 bits
   (Phase 11, 2026-09-20).** `SYSTEM.INT8/16/32/64` are now distinct integer
   types of exactly 1/2/4/8 bytes under both size models
   (`Types.BasicTypeDesc.fixedBytes`; `MemoryLayout.BasicSize`,
   `LLVMTypes.BasicTypeString`, `ConstantEvaluator.MaxMinBound` know them),
   and `rtl/llvm`'s C `int` declarations (`Console`, `Files`, `In`, `Out`,
   `Platform`, `Math`, `MathL`) are written `SYSTEM.INT32`, so the IR says
   `declare void @write(i32, i32, i32)` under `-OC` on i386 as on x86-64.
   *Inclusion* goes by byte width, as in voc (which stores a size on each
   integer type and compares sizes): `Types.Order` gives every numeric type a
   position - twice its rank for the model's own types, which the size model
   moves - and a fixed-width one the position of the widest model type no
   wider than it, so two of one width include each other (`INT32` and
   `LONGINT` under `-O2`, `INT32` and `INTEGER` under `-OC`, `INT64` and
   `HUGEINT` always) and INT8 under `-OC`, narrower than any model type, sits
   below `SHORTINT`. `Types.SetSizeModelIsOC`, called from
   `ConstantEvaluator.SetSizeModel`, is how `Types` (which cannot import
   `MemoryLayout`) learns the model. A constant is typed by the minimal type
   its value fits *under the model*, which under `-OC` is never narrower than
   `SHORTINT`'s two bytes, so `b := 127` for an `INT8` would be refused by
   type; `CheckAssignmentCompatible` accepts an integer constant whose value
   fits a fixed-width type (`Types.FixedIntFits`), the same value-dependent
   escape hatch its string cases already are. Found and fixed on the way:
   `Files.Old` compared a `SYSTEM.ADDRESS` with `MAX(LONGINT)`; `ADDRESS`
   ranks *above* `LONGINT`, so the comparison ran at the address's 32 bits
   and `-OC`'s 2^63-1 truncated to -1 - no file opened on a 32-bit target -
   now compared as a `HUGEINT`. That is a real hole in the `LONGINT <=
   ADDRESS` hierarchy for a 32-bit target under `-OC` (a mixed operation is
   done at the narrower width), left as it is; nothing else in the runtime
   mixes them. Not done: `LONG`/`SHORT` of a fixed-width type (rejected with
   a message), an `INT8` combined with an integer literal under `-OC` (done
   afterwards, Phase 11 step 3: the constant takes the `INT8`'s type), `SET32` (still `SET`)
   and `SET64`. **Result: the self-hosted poc runs on OpenBSD i386.** Built
   there from the Linux cross-compile, it rebuilds itself and emits a
   `Poc.ll` byte-identical to that cross-compile, twice - a fixed point on a
   32-bit machine, the executables byte for byte the same - and the whole
   conformance suite (202 fixtures now: `semantic-system-fixed-width`, a
   model-by-statement table; `llvm-system-fixed-width`, one program built and
   run under both models, only the `LONGINT` line differing;
   `llvm-system-fixed-width-ir`, the declared C signatures at both word sizes
   and both models) passes 202/202 under it, as under the voc-built Stage 0
   there, under the self-hosted poc on NetBSD amd64 and on Linux.

4. **`Modules.Mod`.** `ArgCount-` (a read-only exported `VAR`, set once
   at process start) and `GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR)` —
   command-line argument access, the second concrete example the user
   asked for. Real dynamic module loading (Appendix D2's own sense of
   "Modules") is explicitly out of scope — poc only ever needs the
   argv-access half of what voc bundles under this one module name,
   matching voc's own real `src/runtime/Modules.Mod`, confirmed by
   reading it directly rather than assuming the name implies loader
   semantics here too.
   **Testing**: a fixture that echoes its own `ArgCount`/`GetArg` values
   back, run with a fixed, known argument list from `test.sh`.
   **Implemented (2026-09-20)**: `rtl/llvm/Modules.Mod` has `ArgCount-`,
   `GetArg`, and from voc's module also `ArgVector-`, `GetIntArg` and
   `ArgPos` (the same kind of thing, a few lines each). Not brought over:
   voc's module list and command loading (`ThisMod`, `ThisCommand`,
   `Free`), `BinaryDir` and `MainStackFrame`. The piece that was not just a
   library module: **the program's `main` had no arguments**, so there was
   nothing to read. `LLVMCodeGenerator.GenerateProgram` now emits `define
   i32 @main(i32 %argc, ptr %argv)` for a program that contains a module
   named `Modules`, and its first act is `Modules.Init(argc, argv)` (both
   as words, sign-extended on a 64-bit target), before any module body, the
   same pattern as the collector's stack base. A program without `Modules`
   keeps the argument-less `main`, so no other IR changes. (A user module
   that is itself called `Modules` would get the call too - the same hazard
   as `GarbageCollectedHeap`.) Decisions:
   - **`GetArg` out of range gives `""`**; voc leaves the value as it was,
     so a caller that ignores `ArgCount` reads the previous argument again.
   - **The address of argument `n` is computed in `LONGINT`**: `n *
     SIZE(SYSTEM.ADDRESS)` in `INTEGER` arithmetic wraps at 4096 arguments
     under the 16-bit `-O2` model, and a command line may hold more (voc's C
     promotes to `int`, so presumably it does not have the problem).
   **Testing**: `llvm-modules` (10 checks and a listing, run under poc and
   voc with the arguments `alpha "two words" "" 42 -7`, output equal;
   argument 0, the program's name, is only checked to be there);
   `llvm-modules-extra` (poc only: out-of-range numbers, a 3000-character
   argument, cut to 15 characters or read whole); `llvm-modules-ir` (golden
   `main` for x86_64 and i686); `llvm-modules` also runs as an i686
   executable in `llvm-i686-runtime`, whose `check` now takes the
   arguments to start a program with. 184 pass.

5. **`Out.Mod`/`In.Mod` (Oakwood's own basic pair).** `Out.Char`/
   `Out.Int`/`Out.Ln`/`Out.String` at minimum (exactly poc's own
   `Diagnostics.Mod` usage, confirmed by grep — this is the one module
   this phase builds that's simultaneously a poc-own dependency *and*
   one of the Oakwood Guidelines' basic eight) plus the fuller
   Guidelines interface (`Out.Real`, `In.Int`/`In.Real`/`In.Char`/
   `In.String`/`In.Done`) now that formatted values (`REAL` from Phase 9
   step 2, records/pointers from Phase 9 steps 4–6) actually exist to
   print. `Console.Mod` (step 1) is not superseded — it stays the
   minimal, always-available module; `Out.Mod` is additive. Once real
   `Console`/`Out`/`In` modules exist, cross-checking a fixture using
   them against real `voc` (which has its own working `Console.Mod`
   already exercised by `test/conformance/hello` since Phase 0) becomes
   practical again in a way Phase 8 step 13 found it wasn't for any
   FFI-based fixture.
   **Testing**: fixtures covering each `Out`/`In` procedure, matching
   the Phase 8 predeclared-procedure fixtures' own one-fixture-covers-
   the-whole-set style where practical; at least one cross-checked
   against real `voc` per the paragraph above.
   **Implemented (2026-09-20)**: `rtl/llvm/Out.Mod` has voc's `Out`
   (`Open`, `Flush`, `Char`, `String`, `Int`, `Hex`, `Ln`, `Real`,
   `LongReal`, `Ten`, `IsConsole`) and `rtl/llvm/In.Mod` voc's `In` (`Open`,
   `Char`, `Int`, `LongInt`, `HugeInt`, `Real`, `LongReal`, `Line`, `String`,
   `Name`, `Done`). With them and `Modules`, poc's own `Poc.Mod` and
   everything below it now type-check up to the one known obstacle, the
   `WITH` rule in `SemanticActions.Mod` (step 3's note): `poc
   -emit-llvm-ir` of `ModuleInterface.Mod` is clean and the other two stop
   at exactly those 29 errors. Decisions, read from voc's `Out.Mod`/
   `In.Mod`:
   - **`Out` writes through `Console`** and is as unbuffered as it is, so
     output interleaves with `Console`'s and the trap messages in the order
     of the calls and none is lost when a program ends without an `Ln`
     (voc's `Out` buffers 128 characters and flushes at each line end).
     `Flush` and `Open` do nothing.
   - **`Out.Real`/`LongReal` began as voc's algorithm step for step** and
     printed what voc prints (40 magnitudes at six field widths agreed, on
     x86_64 and i686), not always correctly rounded; Phase 11 step 2 (A3)
     replaced the digit generation by `RealDigits.Digits`, so they are
     correctly rounded and differ from voc where voc is wrong (see there).
     The layout - sign, field width, exponent form - is still voc's, and
     the result is written in one call, not character by character. `Hex` needs no
     `SYSTEM.LSH`/`ROT`; a negative number gets exactly the `n` low digits
     asked for, as in voc.
   - **`Int` has no wrong answer for the smallest `HUGEINT`**, where voc
     (by its source, not run) prints a fixed wrong string.
   - **`In` reads with `getchar`**, one character ahead except at a line
     end, as voc's does. `Real`/`LongReal` read a line, check it is
     `[+-] digits [. digits] [E|D [+-] digits]`, and hand it to libc's
     `strtof`/`strtod`, so the value is correctly rounded (`0.1`,
     `1.7976931348623157E308`, `4.9E-324` and a float tie all come out
     right, checked by their bits); voc goes through `Strings`, cuts the
     line to 15 characters and never sets `Done`. A line that is not a
     number leaves the variable alone and `Done` FALSE.
   - **`In.Name` reads a word**; voc's stops the program ("Not
     implemented"). **`In.HugeInt`** treats hexadecimal digits without an `H`
     as an error, where voc reads them as a garbage decimal number.
     **`In.Open`** only resets the reader: voc also seeks stdin to the
     start, which cannot be done portably and does nothing for a pipe.
   - **voc's own quirks met**: its `In.HugeInt` takes a `SYSTEM.INT64` -
     a variable of type `HUGEINT` is not accepted (err 123) - so `HugeInt`
     is tested only under poc; and voc folds a constant real expression
     such as `1.0D0 / 3.0D0` into its C with 15 digits (the known lossy-
     constants bug), so the shared `Out` test divides values only known at
     run time.
   **Testing**: `llvm-out` and `llvm-in` (run under poc and voc, output
   equal: strings, integers in decimal and hex, 40 powers of ten and their
   reciprocals and other reals at six widths, infinity and not-a-number;
   `In` fed `input.txt` with numbers, hex, lines, a too-long line, a quoted
   string, reals and single characters to the end of the input);
   `llvm-out-extra` (poc only: the smallest `HUGEINT`, a negative field
   width, output with no final line end, interleaving with `Console`);
   `llvm-in-extra` (poc only: `HugeInt`, hex, `Name`, CR LF, reals read
   exactly or refused). All four run as i686 executables in
   `llvm-i686-runtime`, whose `check` now feeds a fixture's `input.txt` as
   standard input. 188 pass.

6. **`Strings.Mod`, `Math.Mod`, `MathL.Mod`.** The remaining Oakwood
   basic modules poc's own source doesn't itself need but the
   Guidelines still call for shipping — `Strings`' simple substring/
   compare/insert/delete operations, `Math`/`MathL`'s REAL/LONGREAL
   trig and transcendental functions. Pure computation, no OS
   dependency, no new backend mechanism — the most self-contained step
   in this phase.
   **Testing**: one fixture per module exercising each exported
   procedure against a hand-checked expected value.

   **Implemented** (`rtl/llvm/Strings.Mod`, `Math.Mod`, `MathL.Mod`; all
   probed against real voc 2026-09-20; the module header comments have the
   full account). Interfaces are voc's - the Oakwood ones plus `Strings.Match`/
   `StrToReal`/`StrToLongReal` and `Math`'s `log`, `ipower`, `sincos`,
   `arctan2`, `fcmp`, `ErrorHandler`/`err`/`ClearError` - so a program
   compiles under either compiler. What a program can observe:

   - **Neither is a copy of voc's.** voc's `Math`/`MathL` are the OOC
     library's polynomial approximations under the LGPL, and poc is
     BSD-3-Clause, so both are written afresh over libm's double functions
     (`sqrt`, `sin`, `exp`, ..., `ldexp`, `logb`, `nextafter[f]`), the same
     names on Linux and the three BSDs. A `REAL` function widens, calls the
     double function and rounds once. **The build now links `-lm`**
     (`LLVMToolchainDriver.Build`; without it `sin` is undefined at link
     time). The error handling is voc's: a call outside its domain reports a
     code through `Math.ErrorHandler` (default: store it in `Math.err`) and
     returns a fixed value (`ln(x <= 0)`: `IllegalLog`, `-large`; the table
     is in `Math.Mod`'s header); `MathL` reports through the same handler.
   - **Where voc is wrong and poc is not**: `sincos` gives voc's cosine as
     `sqrt(1 - sin^2)`, never negative; `succ` of a negative number moves
     down; `pred(1)` is `1 - ulp(1)`, not the true predecessor; `ulp(1)` is
     inexact in both `Math` and `MathL`; `MathL.power(0, 3)` fails; `MathL.small`
     is 0 and its `MathL.large` a little below the true `MAX(LONGREAL)`; `sin`/`cos` give up
     (`LossOfAccuracy`, result 0) beyond about 9099 in `Math`; a denormal's
     `exponent` is -127. Poc's values are exact or correctly rounded, and
     `fraction`/`exponent`/`scale`/`ulp`/`succ`/`pred` are right for
     denormals and zero (`ulp(0)` is the smallest number). `round` (halves
     away from zero, as voc) clamps to `MIN(LONGINT)`/`MAX(LONGINT)` for a
     number that rounds beyond them.
   - **Differences from voc a program could notice**: `exp` reports
     `Underflow` only when the result is really 0 (voc from about e^-88, in the
     denormal range; `MathL.exp` reports none in voc); `sinh`/`cosh`/`arcsinh`
     have no `HypInvTrigClipped`; `log(x, 1)` is `IllegalLogBase`; `arctanh`
     at or past +-1 gives +-`arctanh(1 - 2^-places)` (voc: another
     approximation of the same idea); `power` and `arctan2` follow `Math`'s
     rules in `MathL` too (voc's `MathL` returns `-large` for a negative
     base). `INT16`/`INT32` are `INTEGER`/`LONGINT` (`SYSTEM.INT16`/`INT32` exist since step 7, as the same aliases).
   - **`Strings`** is Oberon-2 over an array and length, all in `LONGINT`
     so nothing wraps, and never writes beyond `dest` or reads beyond a
     string with no `0X`: a result too long is cut to fit *with* its `0X`
     (voc's `Append`/`Extract` can leave it unterminated or write past the
     end). voc's `Insert` past the end of `dest` and `Replace` at a position
     other than 0 do the wrong thing (swapped arguments in a call; too many
     characters deleted) - poc does what the description says. `StrToReal`/
     `StrToLongReal` accept blanks, a sign, either exponent letter in either
     case, and hand the numeral to `strtof`/`strtod`, so they are correctly
     rounded (voc's digit-by-digit conversion can be an ulp off); no numeral
     gives 0, and a numeral over 511 characters leaves the result alone.
   - **A finding for step 8/Phase 11, not fixed here**: a call of a
     *nested* procedure (one declared inside another) compiles to
     `; unsupported: call target is not a plain procedure` and the build
     still succeeds, running with the call silently missing; found when a
     test helper was nested. poc's own source declares none (checked), so
     self-hosting is not blocked, but a silently missing call is a bad way
     to fail; it should be an error at least (or nested procedures should be
     lowered, which needs a static link).
   **Testing**: `llvm-strings`, `llvm-math`, `llvm-mathl` (run under poc
   and voc, output equal: every procedure, compared with the exact value -
   from Python's `math` - to a relative 1e-5 (`REAL`) or 1e-12 (`LONGREAL`),
   the error codes and the values that come back where voc agrees, a
   handler installed in `Math.ErrorHandler`); `llvm-strings-extra` (poc only:
   truncation with a guard byte after `dest`, an insert past the end, a
   replace not at 0, arrays with no `0X`, a string longer than
   `MAX(INTEGER)`, numerals converted exactly, checked by their bits) and
   `llvm-math-extra` (poc only: the constants and `sqrt(2)` by their bits,
   denormals, `succ`/`pred` around 0 and powers of two, the largest number,
   every error at the edge of the range, `round`'s clamps). All five run as
   i686 executables in `llvm-i686-runtime`. 193 pass.

7. **`SYSTEM` (Appendix C), full list.** *(Phase 9 step 4 already
   pulled forward the pseudo-module itself and `ADDRESS`, `ADR`, `GET`,
   `PUT`, `VAL`, `MOVE`, with their lowering - see there; what is left
   below is `BYTE`, `PTR`, `BIT`, `LSH`, `ROT`, `SYSTEM.NEW`, `GETREG`/
   `PUTREG` and the fixed-width types, starting from that foundation.)*
   Unscheduled until now —
   `AGENTS.md`'s own "Appendix C" section has said so explicitly since
   before `PLAN.md` described any phase past 9. Unlike every other step
   in this phase, `SYSTEM` isn't a real `.mod` source file to write: no
   Oberon-2 implementation gives it one, every exported name is
   compiler magic, the same way `PredeclaredProcedures.Mod`'s ordinary
   ~20 names are — so this step is front-end recognition
   (`SymbolTable.Mod`/`SemanticActions.Mod` treating `SYSTEM` as an
   always-available pseudo-module, the same way `Universe` pre-
   populates the ordinary predeclared names, plus argument-shape
   checking for each procedure) *and* `LLVMCodeGenerator.Mod` lowering,
   together, both from a standing start. The full list below was
   re-checked directly against the report's own Appendix C text
   (`pdftotext` on `Oberon2.pdf`, not assumed from memory or from a
   partial/summarized version of the list) — it's larger than this
   step's own first draft had it, which only carried over `ADR`/`VAL`/
   `BIT`/`GET`/`PUT`/`MOVE`/`LSH`/`ROT` and mistakenly also listed
   `SIZE`/`COPY` as if they were `SYSTEM`'s own; neither actually
   appears in Appendix C at all — both are ordinary §10.3 predeclared
   procedures already, no `SYSTEM.` disambiguation ever needed.

   **Two types**: `SYSTEM.BYTE` (`CHAR`/`SHORTINT` assignable to it; a
   formal `VAR` parameter of type `ARRAY OF BYTE` accepts an actual
   parameter of *any* type) and `SYSTEM.PTR` (any pointer type
   assignable to it; a formal `VAR` parameter of type `PTR` accepts any
   pointer type). Both are genuinely new front-end work beyond a bare
   "recognize `SYSTEM` as a pseudo-module" pass — permissive assignment-
   /parameter-compatibility carve-outs in `Types.Mod`, not just argument-
   shape checks on a procedure call.

   **Six function procedures**: `ADR(v)` (address of a variable — typed
   `SYSTEM.ADDRESS`, not the report's own literal `LONGINT`, per
   `AGENTS.md`'s already-recorded follow-up decision, since `LONGINT`
   can't be assumed address-sized once 32-/64-bit parity, Phase 9, is
   real), `BIT(a, n): BOOLEAN` (bit `n` of `Mem[a]`), `LSH(x, n)`/
   `ROT(x, n)` (logical shift/rotation, result typed like `x`; the
   report's own "integer, CHAR, BYTE" argument category explicitly
   includes `HUGEINT` alongside `SHORTINT`/`INTEGER`/`LONGINT`, per
   `AGENTS.md`'s other already-recorded follow-up decision), `VAL(T, x)`
   (reinterpret `x` as type `T`) — and `CC(n): BOOLEAN`, explicitly
   **not** implemented (see below).

   **Five proper procedures**: `GET(a, v)`/`PUT(a, x)` (raw load/store
   at address `a`), `MOVE(a0, a1, n)` (`M[a1..a1+n-1] := M[a0..a0+n-1]`),
   and `SYSTEM.NEW(v, n)` — a *second*, distinct `NEW` overload from the
   ordinary predeclared one (`v: any pointer; n: integer` — allocate a
   raw `n`-byte block and assign its address to `v`, no type/dope-vector
   involvement at all, unlike the ordinary `NEW(v)`/`NEW(v, x0, ...,
   xn-1)` forms Phase 9 step 5/7 build) — needing its own disambiguation
   in both `PredeclaredProcedures.Mod`'s existing `NEW` checking and
   `LLVMCodeGenerator.Mod`'s existing `NEW` lowering, keyed on whether
   the call resolves through `SYSTEM` or through `Universe`. `GETREG(n,
   v)`/`PUTREG(n, x)` are the other two the report defines — explicitly
   **not** implemented, alongside `CC`, for the same reason (below).

   **Explicit non-goal within this step: `CC`, `GETREG`, `PUTREG`.** All
   three are tied to a specific machine's raw register/condition-code
   model — the report's own Appendix C header says so directly ("The
   following specifications hold for the implementation of Oberon-2 on
   the Ceres computer"), and `GETREG`/`PUTREG`'s own definition
   (`v := Register_n` / `Register_n := x`) presupposes a fixed, numbered
   physical register file to index into. LLVM IR has no such thing to
   expose: it's virtual, SSA-form, and register-allocation-agnostic by
   design, with no "register n" or raw condition-code bit surviving
   past an arbitrary instruction sequence for `CC` to test. voc itself
   only type-checks these three (confirmed by reading `OPB.Mod` in
   voc's own source — argument-shape validation only, e.g. `GETREG`/
   `PUTREG`'s register-number-in-range check), not something this
   project has any evidence it lowers to anything meaningful on a
   non-Ceres target either. Nothing in poc's own source, no Oakwood
   module, and no fixture needs them — revisit only if a real, concrete
   need for one surfaces.

   The remaining nine (two types, four function procedures, three
   proper procedures) lower straightforwardly: `ADR` to `ptrtoint`,
   `VAL` to a bitcast-shaped reinterpretation between same-width types,
   `GET`/`PUT` to a raw `inttoptr`-then-load/store at the given address,
   `MOVE` to a byte-by-byte or `llvm.memmove`-backed copy, `BIT` to a
   loaded byte plus a shift/mask test, `LSH`/`ROT` to LLVM's own shift/
   funnel-shift instructions, `SYSTEM.NEW(v, n)` to the same allocator
   Phase 9 step 4 built, called with a raw byte count instead of a
   type-derived size. Does not touch `SYSTEM.INT8..64`/`SYSTEM.SET32/64`
   — those are voc's own extensions beyond `Oberon2.pdf`/Appendix C, not
   something poc's own language needs to match (`PLAN.md`'s own
   bootstrap-terminology section already excludes them from what poc's
   source may use).
   **Testing**: fixtures for each implemented procedure — `ADR`/`GET`/
   `PUT` round-tripping a known value through a raw address, `MOVE`
   copying between two arrays and confirming the byte contents, `BIT`
   testing known-set/known-clear bits, `LSH`/`ROT` against hand-computed
   results for both directions, `VAL` reinterpreting between two same-
   width types, `SYSTEM.NEW(v, n)` allocating a raw block and writing/
   reading through it, `SYSTEM.BYTE`/`SYSTEM.PTR` accepting the
   permissive actual-parameter shapes the front-end carve-out allows —
   all on both the 32-bit/64-bit word-size axis (this step's own
   address-width dependence makes it a second, independent place -
   alongside Phase 9's own cross-cutting discipline - where getting the
   size-dependent axis right from the start matters).

   **Implemented** (`SymbolTable.SystemScope`, `PredeclaredProcedures.Mod`,
   `SemanticActions.Mod`, `Types.Mod`, `LLVMCodeGenerator.Mod`; probed against
   real voc 2026-09-20). Resolving the contradiction above (the step's
   parenthetical lists the fixed-width types, a later paragraph excludes
   them): `INT8`/`INT16`/`INT32`/`INT64` and `SET32` are **implemented**, as
   plain aliases of `SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT`/`SET`; there is no
   `SET64`. Being aliases they have the `-O2` widths (8/16/32/64 bits) and
   are *not* size-model-aware: under `-OC` `SYSTEM.INT32` is a 64-bit `LONGINT`
   and `SYSTEM.INT16` a 32-bit `INTEGER`. That is enough for what the runtime
   needed them for, but the promised migration of the FFI declarations in
   `Platform.Mod`/`Files.Mod`/`Math.Mod` (C `int` written as `LONGINT`) is
   **not done**, since it would only be right under `-O2`; a real fixed-width
   `INT32` (a distinct type, whose width does not follow the model) is a
   Phase 11 row. `CC`, `GETREG` and `PUTREG` are not implemented, as decided.
   What a program can observe:

   - **`SYSTEM.BYTE`** is one byte. `CHAR` and `SHORTINT` values are assignable
     to it, not back (use `VAL`), and it has no `ORD`. A `VAR x: ARRAY OF
     BYTE` parameter takes a variable of any type: the hidden length is the
     actual's size in bytes (for an open-array actual, its element count
     times the element size), so `Copy(x, y)` over two records works like
     voc's. Value `ARRAY OF BYTE` takes only byte arrays (voc too).
   - **`SYSTEM.PTR`** is a pointer to an empty record. Any pointer is assignable
     to it and a `VAR p: PTR` parameter takes any pointer variable;
     `=`/`#` between a `PTR` and any pointer (or `NIL`) is allowed (voc
     rejects the mixed comparison). **Deviation from voc**: a `PTR` cannot be
     dereferenced, type-guarded, tested with `IS`, or be a `WITH` variable
     ("assign it to a typed pointer first"), nor be `NEW`'d as an ordinary
     pointer - voc accepts some of these and the backend cannot lower them
     soundly.
   - **`LSH(x, n)`/`ROT(x, n)`** work at `x`'s own width (`CHAR`/`BYTE`: 8 bits,
     unsigned; `HUGEINT`: 64) and the result has `x`'s type - a `CHAR` shifted
     is a `CHAR` (voc gives a signed integer). A negative `n` shifts or
     rotates the other way. A `LSH` count of the width or more gives 0 and
     `ROT` counts are taken modulo the width; both are defined (voc's are the
     C shifts, undefined there). Lowered branch-free.
   - **`BIT(a, n)`** was voc's, as thought: bit `n` of the `SET`-sized word at
     `a`, `FALSE` outside it. Phase 11 (A11) replaced it by a bit string from
     `a`; see the Phase 11 step 2 bullet on the `SYSTEM` leftovers.
   - **`SYSTEM.NEW(v, n)`** allocates `n` zero-filled bytes (tag 0: the block is
     untraced by the collector, so it must not hold the only reference to
     anything) and assigns the address to any pointer variable `v`. `n <= 0`
     or a size that overflows is the length trap of step 7 of Phase 9 (exit 7,
     "Too many, or negative number of, elements in dynamic array"); a heap
     that cannot supply the block leaves `v` NIL. The call is told from the
     ordinary `NEW` by its designator having a qualifier (`SYSTEM.NEW` - the
     bare `NEW` stays the predeclared one).
   - **Not lowered** (found, not fixed; closed in Phase 11, A10): a guard
     followed by an index (`any(T)[i]`) and a guard to a pointer-to-array type
     stay `; unsupported` in the backend; with `PTR` guards rejected only this
     reaches user code through ordinary pointer types, where it already did.
     Phase 11 made every guard, `IS` and `WITH` on a pointer to an array a
     front-end error, as in voc, so the backend never sees one.

   **Testing**: `llvm-system-shifts` and `llvm-system-bytes` (shared with voc,
   output equal: every `LSH`/`ROT` direction and width, `BIT`, byte-array
   parameters over scalars, records and open arrays, `BYTE` narrowing),
   `llvm-system-extra` (poc only: counts at or past the width, `CHAR`/`BYTE`
   operands, `BIT` numbers past a word or negative, the `INTn`/`SET32` aliases, `PTR`
   comparisons, `SYSTEM.NEW` blocks including a reclaim loop of 20000 blocks
   of 100000 bytes), `llvm-system-new-trap` (exit status 7),
   `semantic-reject-system-byte-ptr` (19 diagnostics). All three run
   fixtures are in `llvm-i686-runtime` and match the 64-bit output; all
   three also build and run under `-OC`. 198 pass.

8. **Self-hosting bootstrap.** Stage 0 (`voc`) compiles all of poc
   (front end + LLVM backend + every `rtl/llvm` module built in steps
   1–6, `SYSTEM` lowering from step 7, and Phase 9's own GC) → Stage 1
   poc compiles poc's own source again, now genuinely linked against
   `rtl/llvm` rather than voc's own runtime → Stage 2 poc compiles it a
   third time; diff Stage 1 vs. Stage 2 output (modulo embedded
   timestamps/paths) for the classic self-hosting fixed point. This is
   the final step of this phase (and of the LLVM-backend line of work
   generally) precisely because it's the one step needing *both* Phase
   9's full language parity *and* this phase's own runtime library —
   the bootstrap terminology section at the top of `PLAN.md` has
   described Stage 0/1/2 since Phase 0, but Stage 1 was never reachable
   until both were done. `SYSTEM` (step 7) isn't itself a bootstrap
   prerequisite — poc's own source doesn't import it (confirmed by the
   same `IMPORT` grep this phase's own Goal cites) — it's grouped into
   this phase for the reasons given there, not because self-hosting
   needs it. Once Stage 1 passes the full conformance suite, `voc` is
   retired from the day-to-day build loop and kept only as a comparison
   oracle (per the bootstrap terminology's own existing wording) —
   `tools/bootstrap/` gains its Stage 1/Stage 2 scripts here, alongside
   Stage 0's existing ones.
   **Testing**: Stage 1 vs. Stage 2 output diff as the fixed-point
   proof; full conformance suite must pass under Stage 1 before `voc`
   is retired from day-to-day use.

**Testing summary**: compile+link+run+diff fixtures throughout (no
purely-static/golden-IR step this time — every module here is either OS-
facing or produces directly observable output), culminating in step 8's
Stage 1/Stage 2 self-hosting fixed point — the point `PLAN.md`'s
"Decisions locked in" table's `voc` framing ("bootstrap compiler...
until poc can compile itself") finally stops applying.
