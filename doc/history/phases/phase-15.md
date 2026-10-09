# Phase 15 — VAX/VMS MACRO-32 backend

Moved here from `PLAN.md` on 2026-10-08, once the phase was done, with
step 9's record written at the close-out. `PLAN.md` keeps the heading,
the goal and a list of the steps. The steps are those of the design,
`doc/developer/vax-macro32-backend.md`, section 12, so a reference
elsewhere to "Phase 15 step N" means step N there and here; the design
holds every decision, each with its date, and the facts behind it, with
their sources in the VMS 5.5 manuals.

The phase's text in `PLAN.md`, as it stood:

`VaxTypes.Mod`, `VaxCodeGenerator.Mod`, `VaxToolchainDriver.Mod` (stub
only — no link/run, per the locked-in decision; assembling, alone, was
allowed on 2026-10-05, below). The design, written before any code, is
`doc/developer/vax-macro32-backend.md`.
**Explicit scope bound** (to prevent drift): targets exactly Phase 8's
narrow vertical-slice feature set (straight-line code, IF/WHILE/CASE,
arrays/records) — *not* full GC/dispatch parity. "Done" means
hand-reviewed `.mar` output checked into
`test/conformance/*/expected-vax.mar`-style fixtures with a reviewer
rationale comment, **each also assembled with `MACRO/OBJECT`** on the
development system, a SIMH VAX running VMS 5.5-2H4 (decided with the user
2026-10-05; the design's §2 and §10) - no linking or running. Linking and
running the output is Phase 16's, which also lifts the vertical-slice bound
above. The bound was widened once, with the user 2026-10-08: the
predeclared procedures `INCL`, `EXCL`, `SHORT`, `LONG` and `ASH`, which
need no heap, are lowered too (the design's step 7b).

**Symbol-name mangling is required, not optional**: VAX MACRO-32 symbols
are limited to **31 characters**. This project's own naming convention
favors longer, descriptive Oberon-2 identifiers (module names, exported
procedure names, qualified `Module.Procedure` forms, type-bound-procedure
dispatch names), which will routinely exceed that limit — unlike the LLVM
backend, which has no such restriction and can emit names close to
verbatim. `VaxTypes.Mod`/`VaxCodeGenerator.Mod` must therefore implement a
deterministic name-mangling scheme (e.g. truncate-plus-hash-suffix) for
every emitted MACRO-32 symbol, and this scheme needs its own fixtures
(long/colliding names deliberately included in the Phase 15 test set) to
confirm two distinct Oberon-2 names never mangle to the same 31-character
symbol.

**External procedures under the VMS Calling Standard**: any procedure
declared external (Phase 6's FFI extension) must be lowered according to
VMS's own well-defined Calling Standard, not poc's internal calling
convention for ordinary Oberon-2 procedures — this is separate work from,
and in addition to, plain MACRO-32 codegen for pure-Oberon code, and its
external-symbol names are subject to the same 31-character limit above.

**How the phase was done.** All of it is on the `vax` branch, with
`main` merged in at convenient points. Two decisions widened what
"done" meant, both with the user: every `expected-vax.mar` is
**assembled** with `MACRO/OBJECT` on the development system, a SIMH
`microvax3900` running VMS 5.5-2H4 (2026-10-05; design §2 and §10), and,
from step 6, a fixture may also **link and run** its `expected-vax.mar`
under the VMS debugger, with stand-ins for poc's runtime routines, and
compare what it leaves with a log (2026-10-06; design §10). Linking and
running poc's own runtime and programs stay Phase 16's. Each step's
`expected-vax.mar` files were drafted by Claude, each with a `;;`
comment saying why the output is right, and reviewed by the user, whose
approval was a commit of its own that changed only the comments' first
lines. The slice was widened once, by step 7b.

**Steps** (design §12):

1. **`VaxTypes.Mod`: sizes, offsets and the name scheme** (`3442fc3`,
   2026-10-06; the proposal for collisions across a link first,
   `b14d217`, 2026-10-05). `MemoryLayout`'s sizes under the VAX's one
   shape (32-bit word, `-O2`), each type's instruction suffix, and the
   name scheme of §5: a 22-character uppercase stem, `_` and 40 bits of
   FNV-1a in base 32, computed a byte at a time; a module's initializer
   `<MODULE>_INIT`, unhashed, and a module name over 26 characters an
   error. `-dump-vax-types` and `-dump-vax-names`. **Found**: a birthday
   search over 12-letter suffixes found a colliding pair after 664,867
   names (one over 5-letter suffixes found none and was killed at 34 GB),
   so a deliberate collision is cheap; and with object libraries a
   collision across modules can link silently. §5.1's answer, accepted by
   the user and amended 2026-10-06: catch collisions, not make them
   rarer, in three layers (the link, a check of the import closure from
   the `.sym` files, unchanged, and poc within a module). Fixtures
   `vax-types`, `vax-names`, `vax-name-clash`, `vax-module-name-length`;
   the hashes agree with an independent Python implementation.
2. **`-emit-macro32` and a module's layout** (`2c894f5`, 2026-10-06).
   `poc -emit-macro32` writes each module compiled from source as
   `<Module>.mar` and implies `-target vax-dec-vms`, which takes only
   `-O2`; the commands that would assemble or link refuse the target
   until Phase 16. `VaxToolchainDriver.Mod` is the stub. §6's layout.
   `tools/vax-assemble` settles open question 2 as scripted telnet (UCX
   3.1 on the guest offers only FTP and TELNET); `test/vaxfixture.sh`
   compares and assembles. Fixtures `vax-empty-module`,
   `vax-declarations-only`, `vax-emit-errors`.
3. **Straight-line code** (`eebaf2c`, 2026-10-06): module variables,
   assignment, integer, `CHAR`, `BOOLEAN` and `SET` expressions.
   Integer arithmetic at the operation's own width with the `IV` bit
   clear, so it wraps (open question 4, decided with the user); `DIV`
   and `MOD` floor; `HUGEINT` a longword pair; values in `R0`-`R5`,
   spilled to the frame when none is free, the body built as a list
   first so the `.ENTRY` mask names exactly the registers written.
   Fixtures `vax-variables`, `vax-integer-arithmetic`, `vax-hugeint`,
   `vax-boolean-char`, `vax-set`, `vax-spill`.
4. **Control flow** (`758ddc4`, 2026-10-06): `IF`, `CASE`, `WHILE`,
   `REPEAT`, `FOR`, `LOOP`, `EXIT`. Every jump to a statement's label is
   `JMP L^`; conditions jump without making a value; `FOR` by compare
   and branch, not `ACBx`, whose reach a long body would exceed; `CASE`
   by `CASEB`/`CASEW`/`CASEL` when its labels are dense. The trap call,
   `POC_TRAP(code, module, line, column)` by `CALLS` (§9, decided with
   the user), is Phase 16's routine. Fixtures `vax-if`, `vax-loops`,
   `vax-for`, `vax-case`. **Found**: an `IF` with an `ELSIF` had its last
   `ELSIF`'s position ("Ongoing bug fixing" 4, below).
5. **Procedures and calls** (`f646c88`, 2026-10-06), then external
   `["VMS"]` procedures. One mechanism (§7): `CALLG` with the argument
   list in the caller's frame, so a recursive call is reentrant; a
   `HUGEINT` value by the address of a copy; a value parameter the body
   changes copied on entry, since the argument list is read-only
   (CallStd 2.3); a function's result in `R0` (`R0`/`R1`), reaching `END`
   trapping (12). Fixtures `vax-procedures`, `vax-parameters`,
   `vax-calls`, `vax-external`.
6. **Arrays, records and strings** (`ad16926`, 2026-10-06), with the
   traps. An index is checked by `CMPL` and an unsigned `BLEQU` over
   `POC_TRAP` code 2, then index mode for elements of 1, 2 or 4 bytes;
   whole arrays and records by `MOVC3`, string constants by `MOVC5`, in
   pieces of at most 65535 bytes; strings compared by `POC_STRCMP`.
   **Found**: a condition's left operand was evaluated after its right,
   the two being arguments of one call whose order voc's C leaves open.
   Fixtures `vax-arrays`, `vax-index-registers`, `vax-records`,
   `vax-strings`, `vax-block-moves`. With this step the fixtures began to
   run under the debugger (`2dc5625`; `tools/vax-run`,
   `tools/vax-runtime-stub.mar`), and the earlier steps' fixtures got
   runs (`77423ed`, `806fab5`). **Found by running**: linking
   `vax-external` gave `%LINK-W-SHRSYMREF` for `LIB$GET_EF` and an image
   based at a fixed address, so every symbol outside the module is now
   named in general mode, `G^` (`83112dd`, decided with the user
   2026-10-06; §7); and `vax-if`'s line 16 was unreachable, now replaced
   by one a run reaches.
7. **The predeclared procedures of the slice** (`e9a4a0e`, 2026-10-08):
   `ABS`, `ODD`, `CHR`, `ORD`, `CAP`, `INC`, `DEC`, `COPY` and `HALT`,
   and `LEN` folded; `CHR` checked under `-range-checks`; `HALT` calls
   `POC_HALT`, a routine so that Phase 16 can run the modules' cleanup
   there first (the user). Fixtures `vax-predeclared`, `vax-inc-dec`,
   `vax-copy`, `vax-range-checks`.
   7b. **`INCL`, `EXCL`, `SHORT`, `LONG` and `ASH`, and `COPY` of more
   than 65535 characters** (`36151ae`, 2026-10-08; the slice widened
   with the user, `PLAN.md`'s text above). `ASSERT` stays outside the
   slice until its trap is settled. Fixtures `vax-incl-excl`,
   `vax-short-long-ash`, `vax-short-checks`, `vax-copy-long`.
8. **Several modules and the program's start** (`c4b9e6f`, 2026-10-08).
   Imported variables and procedures by their home module's symbol in
   general mode, declared `.EXTERNAL`; each initializer calls its
   imports' in `IMPORT` order; each module defines its key, `POC_K1_`
   and the key's 16 hex digits, `== 0`, and its importers declare it, so
   `LINK` reports a stale import undefined (`%LINK-W-NUDFSYMS`, checked
   on the guest; open question 8, decided with the user, the `1` being
   the name scheme's version); the main module's `<MODULE>_MAIN` calls
   its initializer and returns `SS$_NORMAL`, named by `.END` (decided
   with the user). An imported name whose symbol is one of the module's
   is an error at its use (layer 3 of §5.1), and symbol clashes are
   reported as errors, not as constructs not lowered yet. `tools/vax-run`
   links a program's modules with no driver. Fixture `vax-modules`, a
   program of three modules run on the guest, and a cross-module clash
   in `vax-emit-errors`, found by a birthday search between two modules'
   names. Every earlier `expected-vax.mar` gained the key and start
   lines and went back to the user for review (`567bf6d`).
9. **The phase record and the exit review** (2026-10-08): this record,
   and the review below.

**The tools** (`DEVELOPER.md`, section 4). `tools/vax-assemble` and
`tools/vax-run` copy by FTP (active mode, ASCII) and drive `MACRO`,
`LINK` and the debugger by a scripted telnet login
(`tools/vax-login.tcl`), as the unprivileged user `POC`. Since the
fixtures run in parallel, each holds a lock on this host while it uses
the guest (`781922d`, `tools/vax-lock.sh`), and the guest's password is
read from `~/.netrc-poc-vax`, never printed or put on a command line
(the user, 2026-10-08: `~/.netrc` serves the user's other VAX). Each FTP
step is one session, and only `make test`'s suite run uses the guest
(`VAX_GUEST=skip` elsewhere; `8bac6ae`): the VAX fixtures went from 289
s to 137 s per run, and `tools/check-hosts` on four hosts from 21 to
about 5 minutes. A login costs about 0.25 s by FTP and 0.4 s by telnet,
more than `MACRO` (0.15 s) or `LINK` (0.19 s).

**Step 9, the exit review.** The phase's "done" holds: 35 `vax-*`
fixtures, 32 `expected-vax.mar` files (three of them in `vax-modules`)
reviewed by the user, each assembled clean on the guest, and 28
fixtures with debugger runs whose logs match. Beyond the fixtures, every
module of the suite (492) was given to `poc -emit-macro32`: 109 were
written, and every refusal of the others was of something outside the
slice - `REAL` and `LONGREAL`, open arrays, pointers and `NEW`,
procedure values, record extension and records holding pointers or
procedures, nested and type-bound procedures, structured constants,
`["C"]` externals, `SYSTEM`'s `ADR`, `GET`, `PUT`, `VAL` and `MOVE`,
`SYSTEM.SET64`, a `HUGEINT` value parameter of an external procedure
(Phase 17's), and `ASSERT`. **Found and fixed**: an operation or a
comparison on an operand already refused added a second message naming
`REAL` whatever the operand's type was ("this operation (REAL and
LONGREAL are Phase 16's)" for a `SYSTEM.SET64` `+`), and `NIL` was "this
expression". Now the operand's own message is the only one, an
operation or comparison the backend cannot lower names its operands'
types, and `NIL` says it is Phase 16's (case `VaxReportedOnce` in
`vax-emit-errors`). **Left open**, for the phases that follow:

- `SYSTEM.SET64` on the VAX was in no phase's plan, since Phase 16 step 3
  brings what poc's own source uses and only the runtime's `Texts` uses
  it: added to that step (the user, 2026-10-08).
- `ASSERT`, until its trap is settled (step 7b).
- Open questions 1 (the destination machine's VMS version, for the user
  to check), 5 (packed records, Phase 17's), 6 (`LONGREAL`'s format,
  Phase 16's) and 7's remainder (whether the Librarian reports
  `DUPGLOBAL`, unchecked).
- §5.1's layer 2, poc's check of a program's import closure before
  linking, is Phase 16's, with linking; `MULDEF` fatal in every build
  procedure, layer 1, too.
- The runtime routines the fixtures' stub stands in for (`POC_TRAP`,
  `POC_HALT`, `POC_STRCMP`, `POC_HMUL`, `POC_HDIV`, `POC_HMOD`) are
  Phase 16's.

**Exit gate**: `tools/check-hosts` on atla, cymoril, artos and alerik
before each commit (386 fixtures each at step 8, Stage 1 and Stage 2
identical; atla with `check-opt2` and the VAX fixtures against the
guest); rackhir at the close-out, on `567bf6d`, step 8 with its review
(386, Stage 1 and Stage 2 identical, 2026-10-08).

**Testing summary**: every step adds `vax-` fixtures; each
`expected-vax.mar` is reviewed by the user, assembled, and from step 6
run where it has code to run.

## Ongoing bug fixing, during Phase 15

`PLAN.md`'s "Ongoing bug fixing": fixed while Phase 15 was current,
each with a fixture, on `main` and merged into `vax`; moved here at the
close-out, under their numbers there.

1. **[fixed] An imported read-only variable was accepted as a `VAR`
   argument** (found 2026-10-05 implementing read-only parameters,
   "Ongoing language enhancements" 1). `P(M.v)`, with `v-` exported by
   `M` and `P` taking a `VAR` parameter, passed `poc -check`, so `P`
   could change another module's read-only variable; voc says err 76,
   "this variable (field) is read only". `CheckArguments` checked that a
   `VAR` argument was a variable but not that it was writable. Now an
   error, "a read-only variable cannot be a VAR argument", and likewise
   a read-only record as the `VAR` receiver of a type-bound procedure
   (`M.r.Bump`), which voc accepts. Fixture
   `semantic-reject-readonly-param`.

2. **[fixed] `-install-library` over a copy an older poc wrote said
   "rebuild it"** (found 2026-10-05 reinstalling polibfyaml with 0.3.0
   over its 0.2.0 copy). To remove the old copy's files, `InstallLibrary`
   read its manifest through `Libraries.Load`, which refuses one another
   version of poc wrote: so it printed "was written by poc 0.2.0, not
   0.3.0: rebuild it" about the very copy it was replacing, and, the
   manifest refused, left the `.sym` and `.owner` files of any module the
   new copy no longer has. Now it reads that manifest without the
   version, target and size-model checks (`Libraries.LoadInstalled`), and
   outside the libraries loaded for use. Fixture `llvm-using-modules`.

3. **[fixed] A mistyped option was lost in 70 lines of usage text**
   (found 2026-10-05 by the user with 0.3.1). `poc -x` printed the whole
   old usage text - every command, in the "-x may precede -y" style the
   phases had grown - without saying that `-x` was the trouble; and it was
   nothing like `-help`'s short summary, which left out user options
   (`-install-library`, `-lto`, `-trap-heap-exhausted`, the path
   options). Now `-help` lists every command and option, in one table,
   with POC_IMPORT_PATH and POC_LIBRARY_PATH and, in a section of their
   own at the end, the commands for testing poc itself (decided with the
   user); `poc` with no arguments prints the same on standard error and
   fails; an unknown option, a command without its file and options with
   no command after them each get one line saying what is wrong and
   "run poc -help for the commands and options". `Poc.Usage` is gone
   (`Help`, `BadUsage`). Fixtures `poc-usage` (rewritten),
   `poc-output-streams`, `doc-poc-options` (now against `-help`'s list).

4. **[fixed] An IF with an ELSIF had its last ELSIF's position** (found
   2026-10-06 writing the VAX backend's control flow, Phase 15 step 4).
   `ParseStatement` kept each ELSIF's line and column in the variables
   holding the IF's, so `-g` put the IF's first condition on the last
   ELSIF's line. The ELSIFs now have their own. The LLVM backend, too,
   gave an ELSIF's condition the position of the body before it, for
   `-g` and for a trap in the condition; it now sets the ELSIF's own.
   Fixture `llvm-if-lines`.

5. **[fixed] `ORD` of a `SET` did not compile under `-OC`** (found
   2026-10-06 by the user's FLTK binding, in 0.4.0 and before; the
   binding used `SYSTEM.VAL(SYSTEM.INT32, s)` instead). `GenerateOrd`
   truncated the set to INTEGER's width unconditionally, but under `-OC`
   both are 32 bits, and clang refused the IR: "invalid cast opcode for
   cast from 'i32' to 'i32'". The same for `SYSTEM.SET32`. It now
   converts only when the widths differ. Fixture `llvm-ord-set`, under
   both size models.

6. **[fixed] A module compiled alone lost its pointer variables to the
   collector** (found 2026-10-08 with "Ongoing implementation
   enhancements" 3; fix decided with the user the same day). A module's
   root table - the addresses of the pointers among its module-level
   variables, registered with `ModuleTable` so the collector scans them -
   was emitted only in a program that had `ModuleTable`, which a program
   got only when some module called `NEW` or came from a library. So
   `poc -compile G.Mod`, for a `G` with `VAR p*: POINTER TO R` and no
   runtime among its imports, made a `G.o` with no root table, and a
   program given that `.sym` and `.o` that did use the collector freed
   what only `G.p` reached: `G.p.x`, set to 42, printed 1000 after a
   collection. Now every module with such a variable has its root table,
   registered through a weak reference (`declare extern_weak`) to
   `ModuleTable.Register`, called only when it is not null. A program
   that has the collector registers it as before; one without (no `NEW`,
   no library module, so nothing for the pointers to point into) links no
   `ModuleTable` for it (decided with the user: no runtime for a pointer
   variable alone). Fixture `llvm-gc-compiled-roots`; `llvm-gc-roots-ir`
   and the type-descriptor IR fixtures show the tables and the check.

## Ongoing library enhancements, during Phase 15

1. **[done] `OutStr`: `Out`'s output into a string** (user, 2026-10-05, asked
   while working on `~/Repos/Oberon/Ropes`). No runtime module formats
   a number into an `ARRAY OF CHAR` as `Out` writes it: `FormattedOutput`
   only writes to a descriptor (and is internal), `Texts`' writers lay
   numbers out differently and go through a temporary file, and
   `RealDigits` gives only the digits.
   - **Interface**: `Out`'s output procedures - `Char`, `String`, `Int`,
     `Hex`, `Ln`, `Real`, `LongReal` - with `Out`'s parameters followed
     by `VAR s: ARRAY OF CHAR`: `OutStr.Int(x, n, s)`. Not `Open`,
     `Flush` or `IsConsole`, which are about the stream, and not `Ten`,
     which makes a number, not text.
   - **Appends**: each call adds its text at `s`'s first 0X (if it has
     none, its last character is made one first), so a run of calls builds a line as a run of `Out`
     calls does; the caller starts with `s := ""`. `Ln` appends `0AX`,
     as `Out.Ln` writes.
   - **Overflow**: text that does not fit is cut short, silently, and `s`
     always ends in 0X, as poc's `Strings` does. No call writes beyond
     `s`.
   - **The same text as `Out`**: field widths, `Hex`'s digit counts and
     two's complement, correctly rounded reals (`RealDigits`), no plus
     sign. To keep them from drifting apart, both go through a shared
     internal layer (decided 2026-10-05) that formats each value into an
     `ARRAY OF CHAR`: `OutStr` appends what it makes, and
     `FormattedOutput` writes it, padding with runs of blanks so a wide
     field needs no buffer of its width. voc compiles `FormattedOutput`
     for Stage 0 (Phase 11 D11), so whatever it imports must stay within
     what voc accepts.
   - **Fixtures**: each procedure against `Out`'s output for the same
     arguments (field widths below, at and above the text's length; the
     extremes of `HUGEINT`; negative `Hex`; zero, subnormal, infinite and
     NaN reals), appending to a non-empty `s`, and truncation at every
     length of a short `s`.
   - voc has no `OutStr`; a program using it is poc-only. OOC's `IntStr`
     and `RealStr` (`oocIntStr`, `oocRealStr`) are voc's nearest, with
     different interfaces, and are Phase 20's to decide.
   - **Built 2026-10-05**: `rtl/llvm/OutStr.Mod`, over the new internal
     `FormattedText.Mod` (the text of `Int`, `Hex`, `Real`, `LongReal`,
     unpadded, and `Ten`), which `FormattedOutput` now pads and writes.
     `FormattedText` is voc-compilable and in Stage 0's list
     (`tools/bootstrap/stage0`, `STAGE0_RTL_SRCS`). `String` takes
     `str-`, so a string is not copied, and may be `s` itself. Fixture
     `llvm-outstr` (each case written by both, the pairs compared, under
     `-O2` and `-OC`); `poc-link-flags` lists the new object; the
     User's Guide's `Fields` example.

2. **[done] `InStr`: `In`'s input from a string** (user, 2026-10-05, the
   counterpart of `OutStr`). Nothing reads `In`'s tokens from an
   `ARRAY OF CHAR`: `In` reads only standard input, and `Texts`' scanner
   needs a `Text`.
   - **Interface**: `In`'s procedures except `Open` - `Char`, `Int`,
     `LongInt`, `HugeInt`, `Real`, `LongReal`, `Line`, `String`, `Name` -
     with `In`'s parameters followed by `s: ARRAY OF CHAR; VAR pos:
     LONGINT`: `InStr.Int(i, s, pos)`, as `OutStr` puts its string last.
     `Done-`, as `In`'s, says whether the last call found what it was
     asked for. No `Open`: the caller's `pos` is the whole reading state.
   - **The position**: reading starts at `s[pos]`, and a call that
     succeeds sets `pos` to just after the last character it used up
     (the blanks it skipped, the number or word, a string's closing
     quote, a line's 0AX). One that fails leaves `pos` and its argument
     as `In` leaves its argument. The string ends at its first 0X, or at
     `LEN(s)` if it has none; a `pos` below 0 or past that end reads
     nothing (`Done` FALSE), and does not trap.
   - **The same tokens as `In`**: each procedure accepts what `In`'s
     does (decimal or `H` hexadecimal integers with a minus sign, `Int`
     and `LongInt` narrowed to the low bits, a quoted string on one
     line, a word up to the next blank), so the two should share one
     scanner over a source of characters rather than be written twice.
     Except: `In.Real` and `In.LongReal` read a whole line and take it
     as one number; `InStr`'s read the numeral at `pos` (`[+-] digits
     [. digits] [E|D [+-] digits]`), correctly rounded through
     `strtof`/`strtod`, and stop after it, so a string of several
     numbers can be read one after another.
   - **`s` is a read-only parameter, `s-: ARRAY OF CHAR`** (decided
     2026-10-05): a value parameter takes a string constant, but poc
     copies it on entry (`AGENTS.md`, "Open arrays"), so reading a long
     string token by token would cost its length per call; a `VAR s`
     avoids the copy and refuses a constant. voc's `x-` refuses a
     constant too (err 122), so poc adopts it in a version that takes
     one.
   - **Depends on "Ongoing language enhancements" item 1** (read-only
     parameters): `InStr` is built after it, not before with a value
     `s` (the user, 2026-10-05).
   - **Fixtures**: each procedure against `In` reading the same text from
     standard input (the same values and `Done`), `pos` after every kind
     of token and after a failure, a run of tokens read in turn, a
     string with no 0X, and a `pos` at, before and past its end.
   - voc has no `InStr`; a program using it is poc-only. OOC's `IntStr`
     and `RealStr` read numbers from strings, with other interfaces, and
     are Phase 20's to decide.
   - **Built 2026-10-05**: `rtl/llvm/InStr.Mod`, over the new internal
     `FormattedInput.Mod`, which recognizes every token over an abstract
     `Source` (`Ready`, `Current`, `Advance`): `In` now reads through it
     with a `Source` over standard input, and `InStr` with its
     `StringSource`, which reads `s` in place through its address. On a
     failure `InStr` puts `pos` back. Fixture `llvm-instr` (the same calls
     on `input.txt` through `In` and `InStr`, compared, then `InStr`'s
     positions, under `-O2` and `-OC`).

## Ongoing language enhancements, during Phase 15

1. **[done] Read-only parameters, `PROCEDURE P(x-: T)`** (decided with the user
   2026-10-05, for `OutStr` and `InStr`, "Ongoing library enhancements";
   Phase 19's candidate 2 until then; `000-todo.org`).
   `doc/developer/language-extensions.md`, "Read-only parameters", has the rules:
   - Inside `P`, assigning to `x` or any part of it, or passing it or any
     part of it as a `VAR` actual, is a compile-time error. `VAR x-` is an
     error, as in voc.
   - The actual may be any expression: a variable; a constant, a string
     included; any other expression, evaluated into a temporary. voc's
     takes only a variable (err 122).
   - A type of at most 16 bytes, under the size model in force, is passed
     by value, a larger one or an open array by reference, a constant by
     reference to its own storage; the choice is made from the formal's
     type alone, so caller and procedure agree across modules. As in Ada
     (RM 6.2(12)), a program may not rely on which: a read through an
     alias gets the old value or the new one.
   - The `.sym` format records the mark. `-strict` rejects it and needs
     nothing more; poc's own source does not use it.
   - Steps: the parser (the mark, now a syntax error, and
     `parser-reject-param-export-mark`); the checker (the read-only
     rules, any actual, procedure types and type-bound procedures, whose
     parameter lists must then match mark for mark); the `.sym` file;
     the LLVM backend (by value or by reference, the temporary); fixtures
     for each; the guides.
   - **Built 2026-10-05**, as `doc/developer/language-extensions.md`, "Read-only
     parameters", records ("Implemented"). Calling a type-bound procedure
     with a `VAR` receiver on it is an error too. A large one's actual
     that is no variable needs no temporary after all: only a string has
     a record or array type without one, and it is passed as a private
     constant global of the parameter's type. Not compared with voc,
     whose `x-` differs (by reference always, a variable only); the
     fixtures check poc's rules. Found along the way: "Ongoing bug
     fixing" 1.

2. **[done] `SYSTEM.ADDRESS` and an integer type of the same width include each
   other** (found 2026-10-08 by the user porting polibfyaml to OpenBSD
   i386; decided with the user the same day). `Types.Order` gives
   `ADDRESS` the place of the widest integer type of its width, so under
   `-OC` on a 64-bit target, where `LONGINT` and `HUGEINT` are both 8
   bytes, it ranked with `HUGEINT`: a `LONGINT` was assignable to an
   `ADDRESS` but not the reverse, while on a 32-bit target, where the
   `LONGINT` is wider, only the reverse held. So no declaration let
   code mixing the two compile without `SYSTEM.VAL` on both. Now
   `Types.Includes` also holds for `ADDRESS` and any integer type of its
   width (`AddressOfSameWidth`): under `-OC` an `ADDRESS` is assignable
   to a `LONGINT` on every target. The one cell of
   `semantic-address-width`'s table that changes is x86_64 `-OC`
   `LONGINT` "from ADDRESS"; `llvm-address-to-longint` runs it.
   Narrowing stays an error (a `LONGINT` to a 32-bit `ADDRESS` under
   `-OC`, an `ADDRESS` to a 4-byte `LONGINT` under `-O2` on a 64-bit
   target). `-strict` already rejects `SYSTEM`. Mixed arithmetic is
   unchanged: `WiderOf` still gives `ADDRESS` (its `Order` is the
   higher). Built 2026-10-08; `make check` passed on atla, cymoril, artos
   and alerik.

## Ongoing implementation enhancements, during Phase 15

1. **[done] A library's manifest records its link arguments** (found 2026-10-06
   by the user writing an FLTK binding). A library wrapping a native one
   needs native libraries on every link of a program that uses it, and
   the manifest had no line for them, so every client repeated `-link
   -lfltk -link -lstdc++`; without them the link failed on
   `__gxx_personality_v0`. Decided with the user 2026-10-06: each
   `-link <arg>` given to `poc -library` is now used to link the shared
   library itself too (it was left out), and recorded in the manifest as
   a line `link <arg>`, the rest of the line (so a `-link` argument may
   not hold a line break). A program that links the library gets those arguments
   after the libraries' own (for every library it links, through
   `needs` too, each argument once), before its own `-link` arguments. No
   new option.

2. **[done] A module's foreign part may be C++, `<M>.cpp`** (found 2026-10-06
   with item 1). Only `<M>.c` was compiled beside `<M>.Mod`, so a C++
   part needed `-c-flag -xc++`. Decided with the user 2026-10-06: `<M>.cpp`
   is compiled by `clang++` (with `-c-flag`'s arguments, as `<M>.c`'s);
   a module with both is an error. A program or shared library with a
   C++ part, its own or a library's - whose manifest then says `c++` - is
   linked by `clang++`, which adds the system's C++ runtime (libstdc++ on
   Linux, libc++ on the BSDs), so a client needs only the library's own
   `link` lines.

3. **[done] A makefile's up-to-date objects are compiled again** (found
   2026-10-06 by the user, with the FLTK binding's makefile). A
   makefile can compile each out-of-date module with `poc -compile`,
   but building the program then compiled every module whose source poc
   could see again: a module is taken from `<Module>.Mod` before its
   `.sym` and `.o` (Reference Guide, "Where modules come from"), and poc
   compared nothing. Decided with the user 2026-10-08: by default, for
   every module compiled from source (imports, the main module and
   `-compile`), poc still checks it and writes its IR - 0.7 s of poc's
   own 29 s build; `clang -c` is the rest - but runs `clang -c` only when
   the object would differ, judged by content, not file times. The `.ll`
   ends with `@<M>.-build.<stamp>`, the FNV-1a hash of the `clang -c`
   command and the IR, and an object that defines it (`nm -P`) is reused;
   a C or C++ part is compiled with `-MD`, and its `.d` records `#
   poc-build <stamp>`, the hash of the command and every file it read.
   Options are in the stamp through the command and the IR. Not under
   `-lto` (no `nm` of bitcode on the BSDs), for a module given as its
   `.sym` and `.ll`, or in `-library` (its directory is installed, and a
   `.d` would name the build's files); the new option `-rebuild` reuses nothing. poc's own
   build, done again, went from 29.7 s to 1.4 s. A module now declares
   only the runtime procedures its code calls, not all of `ModuleTable`'s,
   `GarbageCollectedHeap`'s and `Modules`' whenever the program has them,
   so that `-compile` alone and `-build` write the same IR. Fixture
   `llvm-object-reuse`.

4. **[done] A module a library has for another target is named** (found
   2026-10-08 by the user, installing the NetBSD package on terhali, whose
   pkgsrc clang came from the NetBSD 10.0 packages; decided with the user
   the same day). poc builds for clang's default target, there
   `x86_64-unknown-netbsd10.0`, while the package's `poc-rtl` is for
   `x86_64-unknown-netbsd11.0`, so every runtime import failed with notes
   that said only that no library for 10.0 had it. The notes on a missing
   import now also name each library on the library path that has the
   module for another target, as they did for the other size model:
   `Libraries.OtherTargets` lists the triple directories with the shell,
   since `Files` cannot read a directory. `llvm-using-modules` checks
   it with a library copied under `sparc64-unknown-netbsd`. INSTALL.md
   section 1 says NetBSD needs pkgsrc's clang for the system's own
   release, and the User's Guide (section 1) and the Reference Guide
   ("Where modules come from") say what the notes show.

A third point found with items 1 and 2 - a library is built twice, once for
`-O2` and once for `-OC` - needs no change: declaring the C-facing
parameters with `SYSTEM.INT32` and `SYSTEM.ADDRESS` keeps one source for
both.

## Peaseblossom 0.3.0

The done items of the three "Ongoing" sections above - read-only
parameters, `OutStr` and `InStr`, and the fix for an imported read-only
variable passed as a `VAR` argument, all in `995e393` - were released
as **Peaseblossom 0.3.0** on 2026-10-05 (decided with the user: a minor
release, since they add features), as `doc/developer/DEVELOPER.md`
section 7 says, and the first release made with `tools/set-version`,
`tools/check-hosts` and `tools/release-files`:

- **The version** was set in `6ebcc04` by `make set-version`, after
  `tools/check-hosts -t check-install -t check-seed` passed on atla,
  cymoril, artos and alerik (345 fixtures at each stage), with
  `check-opt2` on atla. rackhir passed `995e393` and `f3e3b5f`.
- **The tarball** came from `make distcheck` (SHA-256 `932309a9...`,
  3474095 bytes). It is signed, with the signed tag `v0.3.0`, and
  published as a GitHub release.
- **Each package** was made from the published tarball (`makesum`), then
  built and checked on its system: `check.sh` on the build root or
  stage; portlint, portcheck and pkglint clean; packing lists unchanged.
  It was then installed as root, checked with `check.sh` against the
  installed poc, and removed with nothing left. On atla the 0.3.0 RPM
  was installed again afterwards, replacing 0.2.0. `mock` built and
  checked the RPM in a clean Fedora 44 chroot.
- **The RPMs** were signed with `rpmsign`. `tools/release-files`
  gathered them with the other packages and signed `SHA256SUMS`, and
  they were attached to the release.
- **Signing** was done in a terminal of its own, through a `gpg` wrapper
  with `--pinentry-mode loopback`. gpg-agent's pinentry is graphical on
  atla, and appears on atla's screen, not the remote user's.

**Peaseblossom 0.3.1** followed the same day, with the fix of
`58e913d` ("Ongoing bug fixing" 2): reinstalling polibfyaml with 0.3.0
showed that `-install-library` over a copy an older poc wrote said
"rebuild it". It was made the same way:

- **The version** was set in `d9f505e`, after the same four-host check
  passed.
- **The tarball** came from `make distcheck` (SHA-256 `b89c58d2...`,
  3476336 bytes). It is signed, with the signed tag `v0.3.1`.
- **Each package** was built, checked and linted on its system (packing
  lists unchanged), installed as root, checked with `check.sh` against
  the installed poc, and removed with nothing left. `mock` built and
  checked the RPM, and on atla 0.3.1 replaces 0.3.0.
- **The RPMs and `SHA256SUMS`** were signed and attached to the release.

## Peaseblossom 0.4.0

What `main` had gained since 0.3.1 was released as **Peaseblossom 0.4.0**
on 2026-10-06 (decided with the user: a minor release, since it adds
features): the done items of "Ongoing implementation enhancements" (a
library's manifest records its `-link` arguments, and a module's part
may be C++, `03eb4b6`), `-help` listing every command and option
("Ongoing bug fixing" 3), `make doc`'s HTML and PDF documents, in the
tarball and installed, and the fix of "Ongoing bug fixing" 4. It was
made as `doc/developer/DEVELOPER.md` section 7 says:

- **The version** was set in `0f9b196` by `make set-version`, after
  `tools/check-hosts -t check-install -t check-seed` passed on atla,
  cymoril, artos and alerik (347 fixtures at each stage), with
  `check-opt2` on atla. rackhir passed `0f9b196`.
- **The tarball** came from `make distcheck` (SHA-256 `2ba257e2...`,
  4919979 bytes; larger than 0.3.1's for the HTML and PDF documents). It
  is signed, with the signed tag `v0.4.0`, and published as a GitHub
  release.
- **Each package** was made from the published tarball (`makesum`), then
  built and checked on its system: `check.sh` on the build root or
  stage; check-plist, portlint, portcheck and pkglint clean; packing
  lists unchanged. It was then installed as root, checked with
  `check.sh` against the installed poc, and removed with nothing left.
  `mock` built and checked the RPM, and on atla 0.4.0 replaces 0.3.1.
- **The RPMs and `SHA256SUMS`** were signed (`rpmsign` given the key
  with `--define`, as atla has no `~/.rpmmacros`), gathered by
  `tools/release-files` and attached to the release.

**Peaseblossom 0.4.1** followed the same day, with the fix of `3f5e0fa`
("Ongoing bug fixing" 5): the user's FLTK binding found that `ORD` of a
`SET` did not compile under `-OC`. It was made the same way:

- **The version** was set in `bdfd3d2`, after the same four-host check
  passed (348 fixtures at each stage). rackhir passed `bdfd3d2`.
- **The tarball** came from `make distcheck` (SHA-256 `70f7377d...`,
  4941268 bytes). It is signed, with the signed tag `v0.4.1`.
- **Each package** was built, checked and linted on its system (packing
  lists unchanged), installed as root, checked with `check.sh` against
  the installed poc, and removed with nothing left. On the BSDs, Claude
  did the install and removal in the user's root shells in tmux (windows
  2-4), at the user's word, and ran `check.sh` as the user over ssh.
  `mock` built and checked the RPM, and on atla 0.4.1 replaces 0.4.0.
- **The RPMs and `SHA256SUMS`** were signed and attached to the release.
