# Phase 11 inventory

Step 1 of `PLAN.md` Phase 11 ("Settling the open design questions and the TODO
backlog"). Built 2026-09-20 from three sources: the "Open design questions"
section of `PLAN.md`, every entry of `000-todo.org`, and the "not done" /
"found, not fixed" / "revisit" notes scattered through `PLAN.md` (Phases 8-10)
and `AGENTS.md`.

**Verdict column.** `done` is implemented with a fixture. `proposed: ...` is what
the plan already recommends, or what I would recommend; it is *not* decided
until the user confirms it (the language-changing ones especially). `open` means
the item needs investigation before a verdict. `phase 12` / `phase 14+` is out
of Phase 11's scope by the plan's own non-goals. `decided (user, date)` is a
verdict the user has given; only A13, A21 (survey first), C5 (survey first), C6, C7 and C9 have one so far. The verdicts are
written into `AGENTS.md`/`PLAN.md` by steps 2-9, with the evidence.

"Step" is the Phase 11 step that owns the item. "Probed" means checked against
the built `poc` in this inventory pass (2026-09-20).

## A. The Phase 11 table (`PLAN.md`), one row each

| # | Item | Source | Step | Kind | Verdict |
|---|---|---|---|---|---|
| A1 | Value-argument predeclared functions in a `CONST` (`ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`, `LONG`, `SHORT`, `ODD`); `ASH` done | Open design questions | 2 | gap | **decided (user, 2026-09-20): fold them; done 2026-09-20** (`ConstantEvaluator.EvaluateValueFunction`; fixtures `semantic-const-value-functions`, `semantic-reject-const-value-functions`, `llvm-const-value-functions`). Probe notes: voc folds `ORD` of a `CHAR`/one-char string (not `BOOLEAN`/`SET`), `ABS` (integer and real), `CHR` (rejects outside 0..255, "illegal value of parameter"), `CAP`, `ENTIER` (a `LONGINT` constant; `ENTIER(3000000000.5D0)` rejected under both models), `LONG`, `SHORT` (rejects a value that does not fit, "number too large"), `ODD` (a `BOOLEAN` constant); not `LEN`. Each integer result is re-typed to the minimal type its value fits under the model: `ABS(-500)` is `INTEGER` under `-O2` and `SHORTINT` under `-OC`; `LONG(3)` is `INTEGER` under `-O2` and `SHORTINT` under `-OC`; `ORD("A")` is `INTEGER`; `ABS(MIN(LONGINT))` is `HUGEINT` under `-O2` and rejected under `-OC`. Plan: an `EvaluateValueCall` beside `EvaluateAsh` in `ConstantEvaluator.Mod` (`EvaluateDesignator`, and `IsConstantDesignator`); expect some IR goldens to change by folding; note voc's `LONGREAL` literal bug (integral >= 2^31 rejected) when writing fixtures |
| A2 | Computed `REAL`/`LONGREAL` constant of extreme magnitude cannot be exported to a `.sym` (`ParseReal` not correctly rounded) | Phase 9 step 10 | 2 | bug | **decided (user, 2026-09-20): a correctly rounded `ParseReal`; done 2026-09-20** (`DecimalToDouble.Mod`; fixtures `llvm-real-parse-rounding`, `module-interface-extreme-reals`) |
| A3 | `Out.Real`/`Out.LongReal` are voc's algorithm, not correctly rounded (last digits outside ~10^-22..10^22, 17th digit of a LONGREAL) | Phase 10 step 5 | 2 (with A2) | gap | **decided (user, 2026-09-20): port the exact digit generator into `rtl/llvm`; done 2026-09-20** (`RealDigits.Mod`; fixture `llvm-real-digits`; `llvm-out` now holds only what voc prints identically, the rest is in `llvm-out-extra`) |
| A4 | `ENTIER` of a real beyond a `LONGINT` gives garbage (poc `-2147483648`, voc wraps) | Phase 10 step 5 | 3 | decision | open: `HUGEINT` result, or a trap |
| A5 | Nested procedures not lowered (declaration or call is a compile error) | Phase 10 step 6 | 8 | gap, implementation | proposed: lambda lifting by reference, `doc/nested-procedures.md` |
| A6 | `LONG`/`SHORT` reject `SYSTEM.INT8..INT64` | Phase 10 step 8 | 2 | gap | **done** 2026-09-20: by width along the model's chain, as voc; `LONG(LONGINT)`/`SHORT(SHORTINT)` stay errors; `semantic-long-short-width`, `llvm-long-short-width` |
| A7 | Under `-OC`, `INT8` plus an integer literal (`b + 1`) is a `SHORTINT`, not assignable back | Phase 10 step 8 | 3 | gap, decision | proposed: a constant operand takes the other operand's fixed-width type when its value fits; probe voc |
| A8 | `SYSTEM.SET32` is `SET`; no `SET64` | Phase 10 step 8; `000-todo.org` | 6 | gap, decision | open: merge with A20 (`HUGESET`) |
| A9 | `LONGINT` included in `SYSTEM.ADDRESS` by rank; on 32-bit under `-OC` a mixed operation truncates the 64-bit operand | Phase 10 step 8 | 2 | bug | **decided (user, 2026-09-20): place `ADDRESS` by actual width; done 2026-09-20** (`semantic-address-width`, `llvm-address-width-ir`; seven `rtl/llvm` sites now `SYSTEM.VAL`; a 32-bit `-OC` build of poc itself built and checked on Linux 2026-09-20: identical to Stage 1, suite passes under it; the BSD run is still to do) |
| A10 | `SYSTEM.PTR` cannot be dereferenced/guarded/`IS`-tested/a `WITH` variable (voc allows some); a guard followed by an index (`any(T)[i]`), or to a pointer-to-array type, is unsupported in the backend (now a compile error) | Phase 10 step 7 | 6 | decision, gap | open: decide whether either is wanted |
| A11 | `BIT`'s word-based meaning (voc's) differs from the report's `Mem[a]` bit; `SYSTEM.NEW` blocks are untraced by the collector | Phase 10 step 7 | 6 | decision | proposed: keep both, record as decided (both were chosen with voc probed) |
| A12 | Constant `NEW` length <= 0: poc traps at run time, voc rejects at compile time | `000-todo.org`; Phase 9 step 7 | 3 | decision | proposed: match voc (reject constant lengths), keep the run-time trap |
| A13 | Option to make `NEW` trap when the heap cannot satisfy it | `000-todo.org`; Phase 9 step 5 | 3 | decision + implementation | **decided (user, 2026-09-20): a compiler switch** chooses between (a) the pointer left NIL, as today and as voc does, and (b) the program exiting with a failure status and a text message saying the heap is exhausted. Still to settle in step 3: the switch's name, its default (today's behavior is (a); keeping it as the default is the conservative choice), and the exit status and exact wording, documented next to the existing trap statuses. The switch is compile-time, so it lowers `NEW` to a checking entry point, in line with voc's own switch style and Phase 12 step 1's option table |
| A14 | `ASSERT`: add or not, which form, what `-a` means | Open design questions | 3 | decision (+ implementation) | proposed: voc's `ASSERT(x)` / `ASSERT(x, n)`, its own exit status |
| A15 | Collector scans the stack conservatively | `000-todo.org` | 4 | investigation | proposed default: keep it, documented; measure first |
| A16 | `gdb`/`lldb` debugging support | `000-todo.org` | 5 | implementation | proposed: `-g`, four stages |
| A17 | More than 8 open dimensions; copying a value open-array parameter never written | Phase 9 step 7 | 3 | decision | proposed: look up voc's limit; drop the copy elision unless measured |
| A18 | Hand-written guard-then-selector workarounds in the Appendix A predicates | Open design questions | 2 | close | **decided (user, 2026-09-20): leave as written, document that they exist; done** (`AGENTS.md`) |
| A19 | Optional exported-view-only `-show-interface` | Phase 9 step 4a | 2 | decision | **decided (user, 2026-09-20): build it; done** (`poc -show-interface`, `ModuleInterface.Show`; fixture `module-show-interface`) |
| A20 | `HUGESET` (is `SET` already as wide as `LONGINT`?) | `000-todo.org` | 6 | decision | open: answer from voc's `SET32`/`SET64` (see A8) |
| A21 | Relax assignment-compatibility rule 6; assign an `ARRAY OF CHAR` to another; other array types | `000-todo.org` (3 entries) | 6 | decision + implementation | **decided (user, 2026-09-20): the item starts with a survey, not now**, of how existing Oberon and Oberon-2 compilers treat it (the Oberon System's own, voc, and the others as in C5): a string constant longer than or exactly filling the destination, one `ARRAY OF CHAR` assigned to another (fixed to fixed, open to fixed, fixed to open), and what a too-short destination does (truncate, trap, compile-time error). Written down with sources, as the `ASSERT` survey was; only then decide which way rule 6 relaxes, if at all, and whether it extends beyond `ARRAY OF CHAR`. The compiler set and the way of gathering sources are the same as C5's, so the two surveys can share one pass. Nothing is implemented until the survey is in and the user confirms the decision (a change to the language poc accepts). voc's behavior is the known part: it accepts `fileName := name` as an extension (not re-probed for a too-short destination). Local sources seen by `ls`, contents not yet examined: `/usr/local/sw/src/lang/Oberon/` has `AOS`, `Linz-Oberon-V4`, `NativeOberon3`, `obc`, `OberonPlus`, `OfrontPlus` and `vishap`; `~/Reference/Computer/Languages/Oberon/` has the Oakwood guidelines, the Component Pascal, Active Oberon and Oberon-07 (`Oberon-2012`) reports, Crelier's OP2 thesis, Templ's dissertation and more |
| A22 | `CONST`/`TYPE`/`VAR`/`PROCEDURE` in any textual order | `000-todo.org` | 6 | decision | proposed: close at what voc does (section interleaving is done; true forward references not wanted) |
| A23 | Initializers on `VAR` declarations (`x: INTEGER := 0`) | `000-todo.org` | 6 | decision + implementation | proposed: desugar in the front end; needs user confirmation |
| A24 | Record and array literals | `000-todo.org` | 6 | decision + implementation | open: survey; dropping is a legitimate result |
| A25 | Underscores and dollar signs in identifiers (VMS) | `000-todo.org` | 6 | decision + implementation | open |
| A26 | An `Err` module (`Out` on standard error) | `000-todo.org` | 7 | implementation | proposed: `rtl/llvm/Err.Mod`, unbuffered |
| A27 | BSD runs skipped while the BSD hosts were unreachable | Phase 9 step 8 | 9 (and 8's exit gate) | verification | open: **blocked while at home** |

(A8 and A20 are one decision; A6's fix also closes D1.)

## B. In Phase 11's step text but not in the table

| # | Item | Step | Kind | Verdict |
|---|---|---|---|---|
| B1 | Can a `.sym` carry a target-dependent number (`SIZE(T)` of a pointer, size-model `MAX`/`MIN` folded to a value), against "a `.sym` is target-independent"? `-emit-interface` resolves no `-target` | 2 | possible bug | **probed 2026-09-20: yes, it does.** A module with `CONST PtrSize* = SIZE(P)`, `RecSize* = SIZE(R)`, `LongMax* = MAX(LONGINT)`, `SetMax* = MAX(SET)` gives `4/8/2147483647/31` (default and `-target i686`, `-O2`), `4/12/9223372036854775807/63` (`-OC`, 32-bit), `8/16/.../31` and `8/16/.../63` (`-target x86_64`): the `.sym` differs by word size and size model. **But every whole-program command regenerates each import's `.sym` for the actual target and size model** (Phase 9 step 4a): a stale 32-bit `.sym` on disk gave 8 in a 64-bit `-build`, and the default `-build` (64-bit host) also gave 8. Only `-check` of a client, which reads whatever `.sym` is on disk, could see a mismatched one, and only if `-emit-interface` was run with different flags. Options: (a) print the expression, not the value, for a target-dependent constant (needs a dependence flag through folding, and a way to keep an unexported constant it names); (b) keep values, correct `AGENTS.md`'s "a `.sym` is target-independent" to "carries no layout; folded constants are per target and regenerated by the whole-program commands", add a fixture pinning both; (c) reject the combination. **Decided (user, 2026-09-20): (b), done**: `AGENTS.md` corrected, fixture `module-interface-target-constants` pins the four values and the regeneration |
| B2 | A `-strict` switch: reject everything beyond `Oberon2.pdf`, so poc's own source can be checked to stay strict | 6 | decision + implementation | open |
| B3 | Done: `FormatInt` at the minimum `LONGINT`/`HUGEINT` (`module-interface-min-values`) | 2 | bug | **done** 2026-09-20 |
| B4 | Done: an unsupported construct in the LLVM backend is a compile error (`llvm-reject-nested-procedure`) | 2 | bug | **done** 2026-09-20 |
| B5 | Done: `poc` exits with status 1 after reporting an error (`poc-exit-status`) | 2 | bug | **done** 2026-09-20 |

## C. In `000-todo.org` but not in the Phase 11 table

Not one of them has a home in Phase 11's steps.

| # | Entry | What the tree shows | Verdict |
|---|---|---|---|
| C1 | Update `README.md` with the current list of make targets | `README.md` already lists `make`, `test`, `test-lexer`, `stage1`, `test-stage1`, `stage2`, `check`, `clean`. `GNUmakefile` also has `test-parser`, `test-semantic`, `test-modules`, `test-layout`, `test-llvm`, `test-misc`, `clean-build`, `clean-tests` | open: small; the README's "see GNUmakefile" may already cover it. Check and close |
| C2 | Pragmas so `Math.Mod`/`MathL.Mod` can specify `-lm` | The driver passes `-lm` itself (`AGENTS.md`, Phase 10 step 6), so the need that prompted it is met. A per-module link-library mechanism is a library-design question | proposed: decided (driver-level `-lm`); the general mechanism goes to phase 12 |
| C3 | Implement `HUGEINT` arithmetic on 32 bits | `HUGEINT` is `i64` in LLVM IR, which a 32-bit target lowers itself. poc's own source uses no `HUGEINT` (its `LONGINT` is 8 bytes under `-OC`), so the self-host does not exercise it | proposed: done for the LLVM backend; verify with a 32-bit `HUGEINT` fixture (none in `llvm-i686-runtime` found by grep) |
| C4 | Implement `HUGEINT` arithmetic on VAX/VMS (`LIB$`/`OTS$`?) | No VAX backend yet | phase 13 (out of scope) |
| C5 | Check that everything that should raise underflow or overflow does | The report does not define overflow or underflow behavior at all (no occurrence of "overflow", "underflow" or "undefined" in `Oberon2.pdf`'s text; checked 2026-09-20), so there is no "should" yet. The compile-time constant-folding errors are done and are a separate matter | open: **starts with a survey** (user, 2026-09-20), then a decision. The survey covers how existing Oberon and Oberon-2 compilers handle integer overflow, float overflow/underflow, and `DIV`/`MOD` by zero and at the minimum value: the Oberon System's own compilers from ETH (Oberon, Oberon-2/Oberon V4, Oberon-07 and Ceres/RISC targets: trap, wrap, or unchecked), voc (`-x`/`-r`, C's wraparound), Component Pascal/BlackBox, Oberon+, Oberon-07 implementations, and ooc. Written down with sources, as the `ASSERT` survey was. Only then decide whether poc adds any checking, and as what (always, or an option like voc's `-r`); the result also feeds C9 and Phase 12 step 1's safety-check triage. Local sources seen by `ls`, contents not yet examined: `/usr/local/sw/src/lang/Oberon/` has `AOS`, `Linz-Oberon-V4`, `NativeOberon3`, `obc`, `OberonPlus`, `OfrontPlus` and `vishap`; `~/Reference/Computer/Languages/Oberon/` has the Oakwood guidelines, the Component Pascal, Active Oberon and Oberon-07 (`Oberon-2012`) reports, Crelier's OP2 thesis, Templ's dissertation and more |
| C6 | Better error messages than voc's `Halt(99)` ("report a string rather than a number") | **Rule, from the user (2026-09-20): a run-time error poc reports must say in text what happened, not just a number.** Audit of the LLVM backend and `rtl/llvm`, probed with the built `poc`: the seven backend traps (index, `CASE`, NIL, type guard, `WITH`, array length; `LLVMCodeGenerator` `EmitTrap`) and `Files`' unreportable errors (`-- file not created: <name>`, then `Halt(99)`) already print a message to stderr. Cases that print nothing, **all decided by the user 2026-09-20**: (1) integer `DIV`/`MOD` by zero dies of `SIGFPE` (status 136): appropriate, the signal is the report; (2) unbounded recursion dies of `SIGSEGV` (139): appropriate; (3) `HALT(n)` prints nothing: appropriate, `Oberon2.pdf` leaves the meaning of `n` to the operating system; (4) `MIN(LONGINT) DIV -1` dying of `SIGFPE` on x86: appropriate (not probed); (5) a `NEW` the heap cannot satisfy: a compiler switch, see A13. Not poc's to fix: voc-built programs (Stage 0) get voc's own messages | **decided** except the details of A13; no run-time change for (1)-(4). Record in `AGENTS.md` that these end by signal or by `HALT` without a message, on purpose. A `SIGSEGV`/`SIGFPE` handler is *not* wanted, so the `SIGSEGV`-on-alternate-stack idea is dropped |
| C7 | Source location for traps, etc. | Traps print a message and exit with a status, no location (`EmitTrap`). Overlaps step 5's line tables only in the source positions both need; the two are separate features | **decided (user, 2026-09-20): a compiler switch that turns on file name and line number reporting for traps**, so a trap can be located without a debugger (the analogue of GNAT's source location for an unhandled exception, which Oberon-2's traps are the equivalent of). **Default: off**, the plain "just exit" strategy, which costs no code size or time. **Separate from Phase 11 step 5** (`-g` debug metadata): it needs no debugger and no DWARF. To settle in step 3 (not decided): the switch's name (with A13's, both belong in Phase 12 step 1's option table); the message form (`<file>:<line>: <message>`, procedure name too?); which traps carry it (all seven `EmitTrap` sites, and A13's heap-exhausted exit; `HALT` stays silent per C6); how the location reaches the trap (a per-site string constant or a file/line pair passed to a shared trap routine, which keeps the off case identical to today's IR so no golden changes); a nested procedure or a module body needs a defined answer for the location; the location must come from the source module's own file and line, across imports |
| C8 | Finish the parts of voc's modules (`Console`, `Platform`, ...) poc doesn't support yet | Phase 12 step 3 is the module inventory | phase 12 |
| C9 | Double check things that can trap | Vague in `000-todo.org` | **decided (user, 2026-09-20): document which things poc traps and which it does not**, with the second list named honestly (division by 0, ...) rather than left implicit. Not a change to what poc does. Planned as one table in `AGENTS.md` (what a poc user sees, next to the existing NIL/guard/`WITH` trap paragraph), one row per check: what happens (trap with its text and exit status; death by signal; wraps; leaves a value; compile-time error; undefined), whether the C7 location switch reports it, and how it was verified (probed against the built `poc`, and voc for comparison). **Traps today** (from the code and fixtures, each to be re-probed when the table is written): index out of range on fixed and open arrays (exit 2), no matching `CASE` label (3), NIL dereference including `NIL IS T`, `NIL(T)`, a NIL `WITH` variable and a NIL procedure value (4), failed type guard (5), no matching `WITH` guard without `ELSE` (6), `NEW`/`SYSTEM.NEW` with a non-positive or overflowing length (7). **Does not trap, known** (C6): integer `DIV`/`MOD` by zero and `MIN(LONGINT) DIV -1` (`SIGFPE`), unbounded recursion (`SIGSEGV`), `HALT(n)` (silent by design), a `NEW` the heap cannot satisfy (NIL; a switch, A13). **Not yet probed, to be classified when the table is written**: integer overflow in `+ - *` and `ABS`/negation of the minimum; float overflow, underflow and division by zero (IEEE infinity/NaN?); `SHORT`/`CHR`/`ENTIER` of an out-of-range value (A4); a `SET` element outside `0..MAX(SET)` in `INCL`/`EXCL` and `{...}`; `ASH`/`LSH`/`ROT` counts; `COPY` into a short array (truncates); an uninitialized scalar or record (only pointers and procedure values are zeroed); `SYSTEM.GET`/`PUT`/`MOVE` at a bad address; a value open-array parameter copy that exhausts the stack; a string comparison or `LEN` on a non-terminated array. Depends on C5's overflow survey for the overflow rows | **decided** (documentation). Work: a probing pass over the list above, then the `AGENTS.md` table; belongs in step 3 (run-time semantics), after C5's survey |
| C10 | Look at all of voc's command-line switches | Phase 12 step 1 | phase 12 |
| C11 | Consider supporting voc's `eth`, `ooc`, `ulm` RTLs | Phase 12 steps 3-4 | phase 12 |
| C12 | `HUGESET` and real `SET32`/`SET64` | = A8 / A20 | see A20 |
| C13 | Rule 6, `ARRAY OF CHAR` assignment, "expand to any `ARRAY`", "investigate `fileName := name`" | = A21. The last is **already `DONE`** on line 54: it was a real bug in `Diagnostics.Mod`, fixed with `COPY`. The TODO on line 71 is a stale duplicate | see A21 |

## D. In `PLAN.md`/`AGENTS.md` notes but in neither list above

| # | Item | Where | Probed | Verdict |
|---|---|---|---|---|
| D1 | `SHORT` rejects a `HUGEINT` argument ("SHORT requires a LONGINT, INTEGER, or LONGREAL argument") | Phase 9 step 3 note | **still true** | **done** 2026-09-20 with A6 |
| D2 | A type used on the *same source line* it is declared on (`A = INTEGER; B = ARRAY 3 OF A;`) is rejected as a forward reference; voc accepts (per the plan's note; not re-probed against voc here) | Phase 9 step 1 note (`declLine >= node.line`) | **still true** | **done** 2026-09-20: `SymbolTable.DeclaredAtOrAfter` compares the column too, in `ResolveQualidentType` and `LookupBareTypeName`; `semantic-same-line-type-use`, `semantic-reject-same-line-type-cycles` |
| D3 | Procedure-local and other anonymous records get no descriptor and no name; nothing could allocate one until steps 5/6 | Phase 9 step 1 note | not probed | open: check whether a local `TYPE` record can be `NEW`ed, type-guarded, extended |
| D4 | A record value's LLVM type text is cut at 63 characters (`ValueText`, `textLength = 63`) - only a huge record loaded whole | Phase 9 step 5 note | seen in source, not probed | open: likely a silent miscompile or invalid IR for large records |
| D5 | `CC`, `GETREG`, `PUTREG` not implemented | Phase 10 step 7 | - | **decided** in Phase 10 step 7 (name a machine's registers; LLVM IR has none; voc only type-checks them); record in `AGENTS.md`'s SYSTEM notes, as it already is. Nothing left to do |
| D6 | The `SYSTEM.INT32` migration of the FFI declarations (`Platform`/`Files`/`Math`, C `int` written as `LONGINT`) | Phase 10 step 8 note | commit `7212aae` | **done** (the runtime's C ints are `INT32`) |
| D7 | A `PROCEDURE` whose call target is not a plain procedure (nested) silently dropped | Phase 10 step 8 note | - | **done** by B4; the real fix is A5 |
| D8 | Not exportable: a computed real of extreme magnitude | = A2 | | see A2 |
| D9 | The `-OC` `INT8`-with-literal gap, stated in `AGENTS.md`'s SYSTEM notes | = A7 | | see A7 |

## E. Reconciliation notes for `000-todo.org` (edits made 2026-09-20)

1. "Implement constant folding on integer literals" is **already `DONE`**
   (line 22), so `PLAN.md`'s reconciliation remark that it is "still listed as a
   TODO" is out of date. Nothing to do there.
2. Merge the rule-6 trio (`Consider relaxing assignment compatibility rule 6`,
   `Allow direct assignment of one ARRAY OF CHAR to another`, `Expand to any
   ARRAY`) into one entry with sub-items. Delete the stale duplicate "Investigate
   adding fileName := name ..." (already `DONE` on line 54).
3. The rule-6 entry's quoted text reads "`111 < n`"; Appendix A says `m < n`
   (a paste error from the PDF). Fix it.
4. "Consider allowing CONST/TYPE/VAR/PROCEDURE declarations to occur textually in
   any order" is half done (line 56 is `DONE` for the section-order half). Split
   it: the section-order half `DONE` and cross-referenced, the rest a `TODO`
   that A22 proposes closing.
5. The two `TODO` entries about `HUGESET` are one decision (A8/A20).
6. Add entries for what is in `PLAN.md` but not in the file: A3, A4, A10, A11,
   B1, B2, D2, D3, D4 (and D1, which shares A6's fix).

All six were made in `000-todo.org` on 2026-09-20. Beyond them, the entries for
C5, C6, C7, C9, A13 and A21 now carry the decisions and survey-first
requirements recorded above, so `000-todo.org` and this file agree.

## F. Counts

- Table rows (A): 27, none with a verdict recorded yet. The three step 2 items
  already done (B3-B5) are not table rows.
- Items outside the table that need a verdict: B1, B2, C1-C7, C9, D1-D4 (C5 starts with a survey).
- Out of scope (phase 12 or later): C4, C8, C10, C11, and the general form of C2.
- Already resolved, just needing the record: B3-B5, D5-D7, C13's `fileName := name`.
- Blocked while at home: A27 and the BSD parts of A5's exit gate.
