# Phase 11 — Settling the open design questions and the TODO backlog

Moved here from `PLAN.md` unchanged on 2026-09-27, once the phase was done.
`PLAN.md` keeps the heading, the goal, and a list of the steps, so a reference
elsewhere to "`PLAN.md` Phase 11 step N" means step N here.

**Goal**: go back through everything the project has set aside - the
"Open design questions" section at the end of this file, the open
entries of `000-todo.org`, and every "not done" / "not scheduled" /
"undecided" / "revisit" note scattered through `PLAN.md` and `AGENTS.md`
- and give each item a verdict: **decided** (the decision written into
`AGENTS.md`/`PLAN.md` with the evidence it rests on, voc probed and the
report read, not assumed), **done** (implemented, with fixtures), or
**dropped** (with the reason). Nothing leaves this phase as "undecided".
It sits after Phase 10 - poc compiles itself, so a change to the front
end or the LLVM backend is now checked against a real bootstrap - and
before the library work of Phase 12, whose option triage and module
inventory would otherwise be built on unanswered questions.

**Explicit non-goals**: anything Phase 9 step 10 (Catching Up: `CONST`
`ASH`, `CONST` `MAX`/`MIN` of the real types, integer-literal arithmetic
and computed-constant typing) already owns; the `000-todo.org` items about
voc's command-line switches and machine address size/alignment
(`-A44`/`-A48`/`-A88`) and about supporting voc's `eth`/`ooc`/`ulm` RTLs,
which are Phase 12 steps 1, 3 and 4 by design and stay open until then;
and any VAX/VMS work. Poc's own source stays strict `Oberon2.pdf` Oberon-2
throughout (`PLAN.md`, "Bootstrap terminology"): every language extension
adopted here is implemented in the compiler and tested with fixtures, but
poc's own modules never use it, so Stage 0 (voc) keeps building poc.

**The items** (the inventory step re-checks this list against the tree
as it stands when the phase starts, and adds what it finds):

| Item | Source | Kind |
|---|---|---|
| Value-argument predeclared functions in a `CONST` (`ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`, `LONG`, `SHORT`, `ODD`) - `ASH` is done | Open design questions | gap, "real, separate, future work" |
| A computed `REAL`/`LONGREAL` constant of extreme magnitude (`MAX(LONGREAL) / 2`, `1.0D300 * 1.5`) cannot be exported to a `.sym`: `ParseReal` is not correctly rounded, so no text verifies | Phase 9 step 10 | bug, found not fixed |
| `Out.Real`/`Out.LongReal` are voc's algorithm, not correctly rounded (a decimal exponent estimated as 77/256 of the binary one, scaling by a floating-point power of ten exact only to 10^22): the last digits of a number outside about 10^-22..10^22, or the 17th of a LONGREAL, can be off. The same shortcoming as `ParseReal`'s; one correctly rounded converter each way would close both | Phase 10 step 5 | gap, found not fixed |
| `ENTIER` of a real beyond a `LONGINT` gives garbage (poc: `-2147483648`; voc, which wraps: `-727379968` for 10^12 under `-O2`): the report defines `ENTIER` for values that fit, but a `HUGEINT`-valued one - or a trap - would be kinder | Phase 10 step 5 | **done 2026-09-21** (step 3: a trap, exit 8) |
| Nested procedures (a procedure declared inside another) were not lowered by the LLVM backend: a declaration or a call was a compile error (2026-09-20; before that a comment in the IR and a program quietly missing the call). `Oberon2.pdf` §10: "procedure declarations may be nested". Done in Phase 11 step 8 (2026-09-20/21): lambda lifting by reference, `doc/nested-procedures.md`; what a program can observe is in `AGENTS.md` ("Nested procedures") | Phase 10 step 6; found 2026-09-20 | **done** |
| `LONG`/`SHORT` reject `SYSTEM.INT8..INT64` ("requires a SHORTINT, INTEGER, or REAL argument"); voc's go by size along the model's chain (`OPT.ShorterOrLongerType`) | Phase 10 step 8 (fixed-width `INTn`, 2026-09-20) | gap |
| Under `-OC` an `INT8` met by an integer literal in an expression (`b + 1`) is a `SHORTINT` - the literal's own type is at least two bytes there - and cannot be assigned back to an `INT8` without `SYSTEM.VAL` | Phase 10 step 8 (fixed-width `INTn`) | done 2026-09-21 (step 3) |
| `SYSTEM.SET32` is `SET` (the `-O2` width, 64 bits under `-OC`) and there is no `SET64`: the fixed-width sets `INT8..INT64` got | Phase 10 step 8 (fixed-width `INTn`); `000-todo.org` | **done 2026-09-21** (step 6, with `HUGESET`) |
| `LONGINT` is included in `SYSTEM.ADDRESS` by rank, so on a 32-bit target under `-OC` a mixed `ADDRESS`/`LONGINT` operation is done at the address's 32 bits and truncates the 64-bit operand: `size <= MAX(LONGINT)` in `Files.Old` compared against -1 and no file opened (worked around there, not fixed) | Phase 10 step 8 (fixed-width `INTn`) | bug, found not fixed |
| `SYSTEM.PTR` cannot be dereferenced, guarded, `IS`-tested or a `WITH` variable (voc allows some); a guard followed by an index, or to a pointer-to-array type, is unsupported in the backend | Phase 10 step 7 | decision, gap |
| `BIT`'s word-based meaning (voc's) differs from the report's `Mem[a]` bit; `SYSTEM.NEW` blocks are untraced by the collector | Phase 10 step 7 | decision |
| A constant `NEW` length <= 0: poc traps at run time, voc rejects it at compile time | `000-todo.org`; Phase 9 step 7 | decision |
| An option to make `NEW` trap when the heap cannot satisfy it (today: the pointer is NIL) | `000-todo.org`; Phase 9 step 5 | decision + implementation |
| `ASSERT`: add it or not, which form, and what `-a` means | Open design questions | decision (+ implementation) |
| The collector scans the stack conservatively - can it do better? | `000-todo.org` | investigation |
| Debugging support: `gdb`/`lldb` on poc-built programs | `000-todo.org` | implementation |
| More than 8 open dimensions; copying a value open-array parameter that is never written | Phase 9 step 7 | decision |
| Hand-written guard-then-selector workarounds in the Appendix A predicates | Open design questions | close |
| The optional exported-view-only `-show-interface` | Phase 9 step 4a | decision |
| `HUGESET` (is `SET` already as wide as `LONGINT`?) | `000-todo.org` | decision |
| Relaxing assignment-compatibility rule 6; assigning an `ARRAY OF CHAR` to another (`fileName := name`); other array types | `000-todo.org` (three overlapping entries) | decision + implementation |
| `CONST`/`TYPE`/`VAR`/`PROCEDURE` in any textual order | `000-todo.org` | decision |
| Initializers on `VAR` declarations (`x: INTEGER := 0`) | `000-todo.org` | decision + implementation |
| Record and array literals | `000-todo.org` | decision + implementation |
| Underscores and dollar signs in identifiers (VMS) | `000-todo.org` | decision + implementation |
| An `Err` module (`Out`, writing to standard error) | `000-todo.org` | implementation |
| BSD runs skipped while the BSD hosts were unreachable | Phase 9 step 8 | verification |

1. **Inventory and reconciliation.** Walk the three sources above and
   produce the table as a file (or in this section), one row per item:
   what it is, where it came from, what it blocks (if anything), kind,
   and the verdict once it has one. Reconcile `000-todo.org` with what
   the plan already says: it still lists "Implement constant folding on
   integer literals" as a TODO though Phase 9 step 10 owns it; three of its
   extension entries overlap (rule 6, `ARRAY OF CHAR` assignment,
   `fileName := name`); and "`CONST`/`TYPE`/`VAR`/`PROCEDURE` in any
   order" was half done on 2026-09-17 (sections of the first three may
   interleave; see "Declaration order" below). Ask the user about the
   items whose intent the file does not pin down (see step 6) before
   spending time on them.
   - *Done (2026-09-20).* The inventory is `doc/phase-11-inventory.md`: the 27
     rows of the table above (A), five items only the step text names (B),
     thirteen `000-todo.org` entries the table lacks (C) and nine notes from
     Phases 8-10 in neither (D), each with source, owning step, kind and a
     verdict (`done`, `proposed`, `open`, `phase 12`, or `decided (user,
     date)`). It found four table rows no step owns (`Out.Real` rounding, `ENTIER`
     beyond `LONGINT`, the `SYSTEM.PTR` limits, `BIT`/`SYSTEM.NEW`; A3, A4,
     A10, A11: to be given a step, or dropped, when step 2 starts), two
     bugs still present that the plan only mentioned in passing (a type used on
     the line it is declared on is rejected as a forward reference; `SHORT`
     rejects a `HUGEINT`), and two it could not confirm (a procedure-local record
     without a descriptor, a record type text cut at 63 characters). `000-todo.org` is
     reconciled: the rule-6 entries merged and the `111 < n` paste error
     fixed, the stale `fileName := name` duplicate dropped, the declaration-order
     entry split, ten entries added for what was only here. (The remark above
     that integer-literal folding is still a TODO was already out of date: it
     is `DONE`.) User verdicts so far: a compiler switch for `NEW` on an
     exhausted heap (A13); file and line reporting for traps as a compiler
     switch, off by default, separate from step 5 (C7, **done 2026-09-25**:
     `-trap-location`, fixture `llvm-trap-location`); documenting what poc
     does and does not trap (C9, **done 2026-09-21**: `AGENTS.md` "What traps,
     and what does not", fixture `llvm-no-trap-behavior`; it found six things,
     all decided with the user and done: see `000-todo.org`); no change to the deliberately silent
     `SIGFPE`/`SIGSEGV`/`HALT(n)` endings (C6); and surveys of other Oberon
     and Oberon-2 compilers before deciding overflow/underflow behavior (C5,
     **done 2026-09-21**: `doc/overflow-survey.md`; decided with the user: no new
     checks - integer overflow wraps and is documented as doing so, reals are
     IEEE and silent, `DIV`/`MOD` by zero stays `SIGFPE`, `SHORT`/`CHR`/`SET`
     element range stay unchecked, an optional `-r` left to Phase 12 step 1;
     `AGENTS.md` "Overflow, division and reals", fixture `llvm-overflow-wrap`) and
     rule 6 with `ARRAY OF CHAR` assignment (A21, **done 2026-09-21**:
     `doc/array-assignment-survey.md`; rule 6 stays, voc's array rule is
     adopted for every element type, an open array is never assigned - which
     fixed a defect - and an open source too long for its target traps, exit
     9; `AGENTS.md` "Array assignment"). The remaining items keep
     their `proposed`/`open` verdicts until their steps run.

2. **Known defects and unfinished corners.** Small, concrete, each with a
   fixture that fails first.
   - *Done (2026-09-20): `FormatInt`.* It negated its argument, impossible at
     the smallest `LONGINT`, so `MIN(HUGEINT)` (and `MIN(LONGINT)` under `-OC`,
     as wide) was written as a bare `-`. It now takes the digits from
     `q = -(x + 1)` as `AppendLongInt` does. That exposed a second problem the
     first fix could not see: the digits `9223372036854775808` are a numeral
     no type holds, so the reader refused its own file ("integer literal too
     large for HUGEINT"); `PrintConstValue` now writes `-9223372036854775807 -
     1` for that one value. New fixture `module-interface-min-values`, which
     also reads each `.sym` back as source, under both size models; the value
     was checked to survive an import at run time.
   - *Done (2026-09-20, decided with the user): a `.sym` can carry a number
     that depends on the target, and that stays.* A `CONST` folded from `SIZE(T)`
     of a pointer or a size-model `MAX`/`MIN` is printed as its folded value, and
     `-emit-interface` writes it for the `-target` and size model it was given
     (`4/8/2147483647/31` at 32 bits `-O2`, `8/16/.../63` at 64 bits `-OC`,
     and so on). What makes it safe: a `.sym` carries no *layout* (the hidden
     declarations are source; the importer computes offsets itself), and every
     whole-program command (`-emit-llvm-ir`, `-build`) regenerates each
     import's `.sym` for its own target and size model, so a client never sees
     a foreign one; only `-check` of a client, which reads whatever is on
     disk, could, after an `-emit-interface` with different flags. Options not
     taken: print the expression rather than the value (needs a dependence flag
     through folding and a way to keep the unexported constants it names), or
     reject the combination. `AGENTS.md`'s "target-independent `.sym`" now says
     "carries no layout". Fixture `module-interface-target-constants` pins
     both halves: the four (word size, size model) values, and a 32-bit
     `lib.sym` regenerated by a 64-bit `-emit-llvm-ir`.
   - *Done (2026-09-20, decided with the user): `ParseReal` is correctly
     rounded* (option (a) below), and extreme computed reals export. New
     module `DecimalToDouble.Mod`: no floating-point arithmetic decides a
     digit. The numeral is a big integer D and a decimal exponent a; the
     nearest double m * 2^e (m of 53 bits, ties to even, subnormals and the
     overflow threshold included) is found by cross-multiplying instead of
     dividing - "q <= V / 2^e" is "L >= q * F" for two big integers built from
     D, 5^|a| and a power of two - with a binary search for q and one
     comparison of 2L with (2q+1)F for the rounding, on 15-bit limbs (integer
     multiply, add and compare only, so nothing depends on the host's
     floating-point width). The reverse direction, `DecimalToDouble.Digits`,
     is exact too: v = m * 2^e is the integer m * 2^e or m * 5^-e with the
     point moved, so its full decimal expansion is the digits of a big integer,
     rounded to any precision, ties to even. `ModuleInterface`'s formatter is
     now "the shortest precision whose text `ParseReal` reads back exactly",
     at most 17 digits, verified; its search of neighbouring digit strings,
     `Pow10`, `RoughExponent`, `RoundedDigitsValue` and `IntToDigits` are gone.
     Checked against Python's `float()`: `llvm-real-parse-rounding` has 364
     literals (midpoints, ties, the largest and smallest normal and
     subnormal numbers, the overflow boundary, random 1-25 digit numbers of
     every magnitude) and the old routine got 249 of them wrong;
     `module-interface-extreme-reals` exports 15 computed constants of extreme
     magnitude, all equal to Python's shortest repr, and reads the `.sym` back
     to an identical one. The old export of `4.94D-324 * 3.0D0` was wrong
     (`1.3D-323`, now `1.5D-323`). Not done: a REAL literal is still parsed to
     a double first (`realVal`), its exact single-precision rounding left to
     LLVM through `realText`; `Out.Real`/`Out.LongReal` are the next bullet.
   - **A3, done (2026-09-20): `Out.Real`/`Out.LongReal` are correctly
     rounded** (the user asked for it ported rather than dropped as a voc
     compatibility). `rtl/llvm/RealDigits.Mod` is `DecimalToDouble.Digits`
     over `HUGEINT` limbs: the digits of the exact m * 2^e, rounded to the
     precision asked (nearest, ties to even), no floating-point arithmetic
     and so no dependence on the size model or the host. It stays a
     separate module because poc's own source may not use `HUGEINT`/`SYSTEM`,
     and Stage 0 has no way to link a runtime module for voc. `Out` keeps
     voc's layout; a subnormal now prints its digits, the whole-part
     workaround is gone, and the exponent is right where voc's estimate was
     off by one (voc printed `1.0E-21` for the REAL nearest 1E-20, and
     `1.0D+299` for the product of 300 tens). Fixture `llvm-real-digits`
     checks 1080 lines against a Python oracle (`generate.py`, committed);
     the old routine gets 261 of them wrong. `llvm-out`, which requires the
     same output from voc and poc, now holds only numbers voc prints
     correctly; the ones it gets wrong went to `llvm-out-extra`.
   - The plan text of the item above: export extreme computed real constants: tier 2 of `ModuleInterface`'s
     real formatter searches for decimal text that `ConstantEvaluator.
     ParseReal` reads back exactly, and for a value like `1.5D300` written
     as `1.0D300 * 1.5` none does (the bound itself, `MAX(LONGREAL)`, is
     handled by name since Phase 9 step 10). Either make `ParseReal`
     correctly rounded - `references.md` lists Clinger and Steele-White for
     exactly this - or export such a constant as an expression, or refuse
     it with a clear message instead of the current "failed to find a
     round-trip-safe text representation".
   - *Done (2026-09-20, decided with the user): fold them.* `ConstantEvaluator.
     EvaluateValueFunction`, reached from `EvaluateDesignator` and
     `IsConstantDesignator`, and `GenerateExpr` folds an integer-typed call of
     them like `ASH`. voc probed under both models with a 51-row table (the
     inventory's A1 row had the outline); the results agree on every row but
     four, which poc leaves as the report has them (`LONG(LONGINT)`,
     `SHORT(SHORTINT)`, voc's one-byte constants under `-OC`) or does better
     (`ENTIER(3000000000.5D0)` under `-OC`, where voc dies of a `Halt(-8)`).
     The types: `ORD` an `INTEGER`, `ABS` of an integer the minimal type of its
     value, `ENTIER` a `LONGINT`, `LONG`/`SHORT` the checker's. Two things the
     probe turned up: voc's `CAP` masks with 0x5F, so `CAP("7")` is 17X there
     (poc's leaves a non-letter alone, as its generated code does; recorded in
     `AGENTS.md`'s known voc bugs), and `SHORT` of an integer constant is
     always an error in poc, since a constant's minimal type never leaves its
     value room in the shorter one. Fixtures `semantic-const-value-functions`
     (the type table), `semantic-reject-const-value-functions` (the
     diagnostics) and `llvm-const-value-functions` (the values, both models,
     run). The plan text: fold value-argument predeclared functions in `CONST`s, sharing what
     Phase 9 step 10 built for `ASH`: recursively evaluate the argument,
     apply the function's own value transform. Probe voc for each one - which
     it folds, and what it rejects (`CHR` of a value out of range, `ENTIER`
     of a value that does not fit) - and match it.
   - *Done (2026-09-20, decided with the user: option 1, place `ADDRESS` by
     its actual byte width).* `Types.Order` gives `SYSTEM.ADDRESS` the place a
     `SYSTEM.INTn` of the target's word size would have (`Types.
     SetAddressBytes`, fed by `ConstantEvaluator.SetWordSize`); fixtures
     `semantic-address-width` (assignability and the mixed-sum type at both
     word sizes and models) and `llvm-address-width-ir` (`a <= MAX(LONGINT)`
     on i686 under `-OC` is an `icmp` at i64). A sweep of `rtl/llvm` under
     i686/x86_64 x `-O2`/`-OC` found what the check now rejects on 32-bit
     `-OC`: seven sites passing a `LONGINT` length or offset to a `size_t`/
     `long` parameter (`Console.Mod`, `Platform.Mod`, `Files.Mod`), now
     `SYSTEM.VAL(SYSTEM.ADDRESS, ...)`, and `Files.Old`'s `HUGEINT` workaround
     went back to the plain `size <= MAX(LONGINT)`. Run on Linux
     (2026-09-20, with `glibc-devel.i686`): the Stage 0 poc built poc itself
     as a 32-bit `-OC` executable (`-OC -target i686-unknown-linux-gnu`, 5 s);
     that i686 poc, run on the x86_64 target, rebuilt poc with every `.ll`,
     every `.sym` and the executable byte for byte those of Stage 1, and the
     whole suite (219 fixtures) passes under it. Still to run: the same on a
     BSD host (unreachable from home) - done 2026-09-21 on the local OpenBSD
     i386 VM (`cymoril`): its voc-built Stage 0 built poc there as a 32-bit
     `-OC` executable (Stage 1, 10 s), which rebuilt itself (Stage 2: every
     `.sym`, the `Poc.ll` and the executable identical), the `Poc.ll` is
     byte for byte the Linux cross-compile for `i386-unknown-openbsd7.9`
     (`-OC -target ...  -emit-llvm-ir`), and all 237 fixtures pass under it.
     (`tools/bootstrap/stage1` now sets voc's library path itself, as
     `test/testenv.sh` does: a non-interactive `ssh` on a BSD found no
     `libvoc-OC.so` for the voc-built Stage 0 poc.) The plan text follows.
   - *`LONGINT` included in `SYSTEM.ADDRESS`, at a width it does not fit.*
     `Types.Order` puts `ADDRESS` between `LONGINT` and `HUGEINT` by rank,
     whatever the target: right when both are 32 bits or `ADDRESS` is 64, wrong
     on a 32-bit target under `-OC`, where `LONGINT` is 64 bits and a mixed
     comparison or arithmetic operation is emitted at `i32`, truncating it
     (`AGENTS.md`: "a `LONGINT` can be assigned to an address"). The fixture
     that fails first is a program built with `-OC -target i686-...` that
     compares an `ADDRESS` with `MAX(LONGINT)`; `llvm-i686-runtime`'s
     `i686_can_run`/`i686_triple` run it for real where a 32-bit runtime
     exists, and the IR is golden-checkable everywhere. Two ways out, decide
     between them: place `ADDRESS` by its actual byte width the way `INTn`
     are (`Types` would learn the word size as it learned the size model, via
     `ConstantEvaluator.SetWordSize`; but then a `LONGINT` is no longer
     assignable to an `ADDRESS` on that target, and the runtime's few uses need
     `SYSTEM.VAL`), or keep the hierarchy for assignment and do a mixed
     *operation* at the wider actual width. Either way sweep `rtl/llvm` for
     the same shape (only `Files.Old` was found, by grepping `MAX(LONGINT)`;
     `Files.Mod` compares through `SYSTEM.VAL(HUGEINT, ...)` meanwhile).
   - *Done (2026-09-20): `LONG` and `SHORT` of `SYSTEM.INT8..INT64` and of
     `HUGEINT`* (also the "`SHORT` rejects a `HUGEINT`" bug, `doc/phase-11-
     inventory.md` D1). Probed against voc under both models with a matrix
     over every integer type; poc's result types are identical for the eight
     `SYSTEM.INTn`/`HUGEINT` operands (28 rows), and differ only where poc
     keeps the report: `LONG(LONGINT)` and `SHORT(SHORTINT)` stay errors, voc
     accepts them. `Types.IntegerBytes`/`LongShortByWidth`/`LongerInteger`/
     `ShorterInteger` hold the rule, used by both `CheckLong`/`CheckShort` and
     `GenerateLong`/`GenerateShort`; `SYSTEM.ADDRESS` is not chained (its width
     is the target's). Fixtures `semantic-long-short-width` (the table, every
     type under both models) and `llvm-long-short-width` (the values), and the
     two rows of `semantic-system-fixed-width` changed as predicted. The
     earlier plan text follows. voc's rule (read in
     `OPT.ShorterOrLongerType`, 2026-09-20; probe it before relying on this
     summary) goes by *size along the size model's own chain*: `LONG(x)` of
     an integer is the narrowest of `SHORTINT`/`INTEGER`/`LONGINT` strictly
     wider than `x`, else `INT64`; `SHORT(x)` the widest strictly narrower,
     else `INT8`. So `LONG(INT32)` is a `LONGINT` under `-OC` and an `INT64`
     under `-O2`, and the result is a model type, not an `INTn` of the next
     width. poc's `CheckLong`/`CheckShort` (`PredeclaredProcedures.Mod`) and
     `GenerateLong`/`GenerateShort` (`LLVMCodeGenerator.Mod`) identify their
     operand by type identity (`SHORTINT`, `INTEGER`, `LONGINT`, `REAL`
     only) and refuse anything else, so both grow a size-driven branch for a
     fixed-width operand; the two `LONG(i)`/`SHORT(q)` rows of
     `semantic-system-fixed-width` record the current refusal and change with
     it.
   - *Done (2026-09-20): a type used on the line it is declared on.* `A =
     INTEGER; B = ARRAY 3 OF A;` on one line was rejected as a forward
     reference: `SemanticActions.ResolveQualidentType` and `ConstantEvaluator.
     LookupBareTypeName` compared only the declaration's line with the use's
     (`doc/phase-11-inventory.md` D2, found in Phase 9 step 1). Both now call
     `SymbolTable.DeclaredAtOrAfter`, which compares the column too. voc
     accepts the backward use and rejects the forward one (`B = ARRAY 3 OF A;
     A = INTEGER;`); the self-referencing `S = ARRAY 3 OF S` was reported as
     a forward reference only by accident of the line-only test and is now the
     cyclic-declaration error (voc: "recursive type definition"). Fixtures
     `semantic-same-line-type-use`, `semantic-reject-same-line-type-cycles`;
     the `SIZE(T)` line of the first fails without the `ConstantEvaluator`
     half.
   - *Done (2026-09-20): a construct the LLVM backend cannot lower is an
     error.* Every one of `LLVMCodeGenerator.Unsupported`'s 34 sites wrote a
     `; unsupported` comment into the IR and let the build succeed - a program
     quietly doing less than its source. Now each is an error naming module and
     statement line (`ReportUnsupported`), `GenerateProgram` counts them
     (`unsupportedCount`), and `EmitIR`/`Build` write nothing when any was met.
     Poc's own IR and every fixture's had none, so nothing else moved. New
     fixture `llvm-reject-nested-procedure` (since renamed
     `llvm-reject-external-vms`, once nested procedures were lowered).
   - *Nested procedures.* The feature the change above makes visible: now
     step 8 below, planned in `doc/nested-procedures.md`.
   - *Done (2026-09-20): exit status.* `poc` returned 0 whatever happened, so
     `make` and scripts could not tell a failed build from a good one. A
     module-level `failed` in `Poc.Mod` is set at every place a failure is
     reported (every "poc: ..." message, bad usage, the unsupported-construct
     summary), and after `Run` the process ends with `Platform.Exit(1)` if it
     is set or `Diagnostics.errorCount` or `LLVMCodeGenerator.unsupportedCount`
     is nonzero. `Platform.Exit(code: LONGINT)` is voc's, which
     `rtl/llvm/Platform.Mod` now has too (C `exit`, which flushes stdio); the
     poc built by voc and the one built by poc behave alike. New fixture
     `poc-exit-status` (18 command lines, status only). The bootstrap scripts
     (`set -e`) now stop on a failing `poc`. Found on the way: an unregistered
     `Files.New` file is left behind as `.tmp.<n>.<pid>` in both runtimes, and
     voc's `Files.Delete` renames rather than unlinks, so a failed `-emit-llvm-ir`
     registers its file and `Platform.Unlink`s it (which also removes a stale
     `.ll` from an earlier run); the two new fixtures fail on a leftover temp
     file, and `.gitignore` covers them.
   - Close the two "revisit opportunistically" notes by decision, not by
     work: the guard-then-selector workarounds in `Types.Mod`,
     `MemoryLayout.Mod` and `SemanticActions.Mod` stay as written (they
     are correct, tested, and rewriting the Appendix A predicates for style
     is a risk with no payoff - decided with the user 2026-09-20, and
     recorded in `AGENTS.md` where the workarounds are described);
     `-show-interface` is built (below).

   - *Done (2026-09-20, the user wanted it built): `poc -show-interface
     <file>`.* Prints a checked module's exported view on standard output, as
     voc's `showdef` does: exported constants, types, variables and
     procedures, and of each record only its exported fields and type-bound
     procedures (a `.sym`, which since Phase 9 step 4a carries the hidden
     ones too, no longer serves as that view). It is `ModuleInterface.Write*`'s
     own printers with `exportedView` set (`ModuleInterface.Show`), so the two
     cannot disagree on how a declaration reads; a procedure is a plain
     `PROCEDURE` heading, not the `.sym`'s body-less `PROCEDURE^`; an
     unexported type an exported signature mentions is named, not declared, so
     the view is for reading and is not source an importer could check. Like
     `-emit-interface` it needs the imports' `.sym` on the import path and
     writes nothing. Fixture `module-show-interface` (a module with hidden
     fields, methods, types, constants, variables and procedures, next to its
     `.sym`, and an importer). `-import-path`, `-target` and `-O2`/`-OC` apply
     as for `-emit-interface`.

3. **Run-time semantics.** Each of these is a place the report is silent
   and voc chose something; the step probes voc, writes down what it does
   and what poc does, and decides.
   - *Done (2026-09-21): an integer literal next to a `SYSTEM.INT8`, under
     `-OC`.* voc's rule, read in `OPB.Op`/`OPT.IntType` and probed under both
     models (a matrix of `+ - * DIV MOD`, comparisons, `INC`/`DEC`, `FOR`,
     `CASE`, arguments and `RETURN` over `INT8`..`INT64`, `SHORTINT`, named
     constants and constant subexpressions): voc types every constant by the
     fewest bytes its value needs whatever the model (`b + 1` is an `INT8`
     under `-OC`), and a constant that does not fit leaves the sum at the wider
     type, so `b + 127` compiles and `b + 128`/`b + 200` do not. poc keeps its
     model-minimal constant types (they show elsewhere) and adds only the
     adoption: `Types.ConstantAdoptsType(constType, otherType, value)` - an
     integer constant whose type is wider than a `SYSTEM.INTn` operand's, and
     whose value fits it, takes it - applied where the operation's type is
     chosen, `SemanticActions.AdoptConstantOperandType` in `CheckBinaryExpr`
     and `LLVMCodeGenerator.AdoptConstantOperands` in `GenerateBinaryExpr`
     (re-emitting the constant, always one immediate, at the other's type), for
     `+ - * DIV MOD` only: a comparison's BOOLEAN result and the fit make
     widening the other operand equivalent. Every probed line accepts or
     rejects as voc does. **Found on the way:** `CASE` on an `INT8` under `-OC`
     built invalid IR (`sext i16 1 to i8`; a label constant is at least two
     bytes there), the same for a one-byte `SHORTINT` under `-O2` with a label
     above 127, because the checker never compared a label with the selector's
     range; voc rejects such a label (err 60), so poc now does
     (`CaseLabelFits`; both ends of a range, where voc looks only at the low
     end) and the code generator narrows a label with `trunc`. Fixtures
     `semantic-system-fixed-width` (21 rows), `llvm-system-int8-constants`
     (poc and voc, both models, one output), `semantic-case-label-range`. The
     earlier plan text follows. A constant's
     type is the minimal one its value fits *under the size model*, which under
     `-OC` is never narrower than `SHORTINT`'s two bytes, so `b + 1` for an
     `INT8` `b` is a `SHORTINT` and `b := b + 1` is refused (a constant *by
     itself* is already assignable to an `INTn` if its value fits, via
     `Types.FixedIntFits`). Probe voc: how does it type a constant met by a
     narrower operand, and does `b := b + 1` compile there under `-OC`? The
     likely rule to adopt is that a constant operand takes the other operand's
     fixed-width type when its value fits it. It has to be applied in two
     places that each pick the operation's type from `Types.WiderOf` on types
     alone - `SemanticActions.CheckBinaryExpr` and `LLVMCodeGenerator.
     GenerateBinaryNumeric`/`GenerateRelational` (whose callers, unlike they,
     hold the expression node to test for constness) - or the two disagree.
   - *A constant `NEW` length <= 0.* voc rejects it at compile time
     ("illegal value of constant"); poc's `NEW` traps at run time (exit 7)
     for any non-positive length. Default to matching voc - reject a
     constant one in `PredeclaredProcedures.Mod` with a diagnostic naming
     the argument - and keep the run-time trap for non-constant lengths.
   - *`NEW` on an exhausted heap.* Today the pointer is left NIL and the
     next dereference traps (voc's behavior). Decide whether a switch for
     "trap right at the `NEW`" is wanted, and what shape it takes: a
     compile-time flag that lowers `NEW` to a checking entry point (the
     natural fit with voc's own switch style and with Phase 12 step 1's
     option table), or a run-time setting in `GarbageCollectedHeap`.
     Implement the one chosen; the trap gets its own exit status and text,
     documented next to the existing ones.
     **Done 2026-09-25**: `-trap-heap-exhausted` (compile-time, off by
     default), exit status 11, "heap exhausted: NEW cannot allocate the
     block"; fixture `llvm-heap-exhausted`.
   - *`ASSERT`.* Resolve the open question with its own survey already in
     hand (every dialect adds one; the dominant form is `ASSERT(x)` and
     `ASSERT(x, n)`, `n` an implementation-defined code; voc gates it
     behind `-a`, on by default; Wirth's Oberon-07 has only `ASSERT(b)`).
     Recommended: adopt voc's two-argument form, lowered as a trap with
     its own exit status when `x` is FALSE and `n` reported, and decide in
     the same step whether `-a` (assertions off) is worth having and
     whether the message-string overload is - no surveyed dialect has it.
     If adopted it becomes the twenty-first predeclared procedure, so
     `PredeclaredProcedures.Mod`, the LLVM lowering, the `Usage` text and
     `AGENTS.md`'s "the report has no `ASSERT`" note all change; fixtures
     cross-check the two-argument form against voc.
     **Done 2026-09-25** (user): as recommended, `doc/assert-survey.md` has
     the survey and the decision - both forms, `n` a constant in 0..255, a
     trap with status 10, a constant FALSE condition a compile-time error,
     no switch, no message-string form; fixtures `llvm-assert`,
     `semantic-reject-assert`.
   - *Open-array limits.* Decide whether more than 8 open dimensions is
     worth supporting (voc's own limit is the thing to look up) and
     whether skipping the copy of a value open-array parameter that the
     procedure never writes is worth doing; the second is a code-size
     and speed matter, so it needs a use of the parameter analysis the
     compiler does not yet have - drop it unless a measurement says
     otherwise.
     **Done 2026-09-25** (inventory A17): no limit - the backend's lengths
     are a list and a call's argument text grows (voc has no limit on the
     type either, only `LEN(a, n)`'s `n` <= 127) - and the copy elision is
     dropped: all copying is 0.17% of poc compiling itself, the collector
     91% (recorded on A15).
   - *`ENTIER` of a real beyond a `LONGINT`* (inventory A4, given to this step
     2026-09-20). Today poc gives garbage (`-2147483648`) and voc wraps
     (`-727379968` for 10^12 under `-O2`); the report defines `ENTIER` only for
     a value that fits. Decide between a `HUGEINT` result (a constant
     `ENTIER` folded in a `CONST` already rejects what does not fit, per voc)
     and a run-time trap in the style of this step's other traps; probe voc
     under both models first, and let A1's `CONST` folding follow the choice.
     **Done 2026-09-21, decided with the user: a trap.** voc's `SYSTEM_ENTIER`
     is a bare C cast (32-bit wrap under `-O2`, INT64_MIN under `-OC`); the A2
     and Oberon V4 compilers (`fistp`) and obc do not check either, and all type
     the result as the standard integer type, as do the report, Component Pascal
     and (as `FLOOR`) Oberon-07. So the result stays `LONGINT` (a `HUGEINT` one
     helps only `-O2` and breaks `n := ENTIER(x)`), and `GenerateEntier` checks
     the range first - 2^(w-1) as an exact float bound, ordered compares so a NaN
     fails - and traps, exit 8, "ENTIER argument out of range for LONGINT"
     (`entierTrapGlobal`, `needEntierTrap`); the `fptosi` it replaces was poison
     for such a value. The `CONST` folder already rejected the same values at
     compile time. Fixture `llvm-entier-trap`; `AGENTS.md` has the behavior.

4. **Can the collector do better than scanning the stack conservatively?**
   An investigation with a written answer. The collector already traces
   heap blocks through their type descriptors; only the stack (and
   registers) are scanned without type information, so the questions are
   what that costs and whether fixing it is worth it. Measure first: a
   fixture that builds structures, drops them, and counts what survives a
   collection at both word sizes (a false pointer is likelier with 32-bit
   words), and the run time of the collector on poc compiling itself.
   Then lay out the options with what each needs - keep conservative
   scanning and document its limits; a shadow stack of live pointer roots
   maintained by the generated code; LLVM's own `gc`/statepoint stack
   maps - and their cost in generated-code size and in portability to the
   four Unix-likes (and, later, VAX/VMS, where the backend has no LLVM
   to lean on: the answer must not be one the VAX backend cannot follow).
   voc's own runtime is the comparison. The default outcome is "keep it,
   documented"; anything more is a separate, sized proposal, not work done
   in this step.

5. **Debugging support for `gdb` and `lldb`** (both are installed).
   Emit LLVM debug metadata from `LLVMCodeGenerator` under a new `-g`
   option, in stages, each ending with a fixture that drives the debugger
   in batch mode and checks its output:
   (a) line tables and subprogram names - a breakpoint on
   `Module.Procedure` and a backtrace of Oberon frames with source lines,
   which needs every AST node's line and column carried down to the
   instructions the generator emits; **done 2026-09-26** (`AGENTS.md`,
   "Toolchain: LLVM"; statement positions, which were already carried
   down for `-trap-location`; `-g` leaves the optimization level alone,
   user);
   (b) parameters and locals of the basic types, so `print`/`info locals`
   show values; **done 2026-09-26** (value and plain `VAR` parameters,
   locals; Oberon type names through typedefs; module variables not yet);
   (c) records, arrays, pointers, and type-bound procedures - a record
   printed field by field, with Oberon type names; **done 2026-09-26**
   (fixed arrays, pointers - to an open array untyped - procedure
   variables, `SYSTEM.PTR`, `VAR` record parameters and receivers, module
   variables with a compile unit per module; described from `Types` and
   `MemoryLayout`, which the VAX backend has too);
   (d) what the calling convention hides: a `VAR` record's type tag and an
   open array's lengths presented as one variable, not as extra
   parameters. **done 2026-09-26** (open-array parameters with their
   lengths as artificial `LEN(a)` variables, pointers to open arrays as
   their heap block, a nested procedure's enclosing variables; a `VAR`
   record shows its static type, the tag left out; lldb does not
   evaluate the dynamic counts, see `AGENTS.md`, "Toolchain: LLVM"). Decide how far to go from what the debuggers' DWARF
   support can express, and record what is left out. The source
   positions and the type descriptions built here are also the inputs
   Phase 16 step 5 needs for the VAX debug and traceback records, so they
   are kept in a form the second backend can read, not folded into the
   LLVM emitter.

6. **Language-extension decisions.** Each item below is a decision first;
   the implementation follows only for the ones adopted, after the user
   has confirmed the decision (these are changes to the language poc
   accepts, not internal choices). For each: what `Oberon2.pdf` says, what
   voc does (probed), what the other Oberon dialects do where that is
   informative (the way the `ASSERT` survey was done), the recommendation,
   and the consequences for `.sym` files, both backends and the VAX plan.
   A new switch, `-strict`, is decided here too: with it poc rejects
   everything beyond `Oberon2.pdf` (its own extensions - `HUGEINT`,
   `SYSTEM.ADDRESS`, external procedures, and whatever this step adds -
   included), which is how poc's own source can be *checked* to stay
   strict instead of relying on convention.
   **`-strict` done 2026-09-25** (user, as recommended): the command-line
   module's own source, not its imports; `make check-strict` over `src/` in
   `make check`; see `doc/language-extensions.md`, "-strict", for the list,
   the `SYSTEM.SET64` poc's own source used, and the two leniencies fixed for
   every mode.
   - *Assignment of one `ARRAY OF CHAR` to another, and rule 6.* **Done
     2026-09-21 (inventory A21):** the survey is `doc/array-assignment-survey.md`;
     rule 6 stays as it is, voc's array rule is adopted for every element type
     (fixed array no longer than the target, or an open array; whole array
     copied by size; a longer open source is a trap, exit 9), an open array is
     never assignable (a checker/backend defect fixed), and `-strict` must
     reject the extension. `AGENTS.md` "Array assignment". What follows is the
     original plan. The three
     overlapping `000-todo.org` entries. `000-todo.org` does not say in
     which direction rule 6 ("a string constant with m characters assigns
     to an `ARRAY n OF CHAR` when m < n") is to be relaxed - exact fit
     `m = n`, or a longer string truncated - so the step begins by asking
     and by probing what voc accepts. For `fileName := name` voc's
     behavior (accepted, an extension) is the known part; what it does
     when the destination is too short (truncate like `COPY`, or trap) is
     to be probed. "Expand to any `ARRAY`" needs a use that is not
     `ARRAY OF CHAR` before it is worth the semantics of a partial copy.
   - *Declaration order.* The section order half is done (2026-09-17,
     voc-verified: `CONST`/`TYPE`/`VAR` sections may repeat and interleave,
     but every use still follows its declaration and no `TYPE`/`VAR`
     follows a `PROCEDURE`). What remains is true forward references and
     interleaving procedures with the rest. The default is to close the
     item at what voc does, since true forward references mean a
     multi-pass resolver for every declaration kind and the `PROCEDURE^`
     forward declaration already covers the case that matters. Reopen only
     for a concrete need.
     **Decided 2026-09-25 (user): declare-before-use stays; `CONST`/`TYPE`/
     `VAR` sections may also follow procedures** (as in Active Oberon and
     Oberon+), so declarations can sit near the procedures that use them. An
     extension, rejected by `-strict`; a late declaration may not hide a name
     visible from an enclosing scope, and a `POINTER TO` base must be
     declared before the next procedure. Done: `doc/language-extensions.md`,
     "Declarations after procedures"; fixtures
     `llvm-declarations-after-procedures`,
     `semantic-reject-declarations-after-procedures`,
     `semantic-strict-declarations-after-procedures`.
   - *`SYSTEM.PTR` and the `SYSTEM` leftovers* (inventory A10 and A11, given to
     this step 2026-09-20). (1) A `PTR` cannot be dereferenced, guarded,
     `IS`-tested or used as a `WITH` variable, where voc allows some; and a
     guard followed by an index (`any(T)[i]`), or a guard to a
     pointer-to-array type, is a compile error in the backend. Decide whether
     either is wanted; the default is to keep the first (it is what makes a
     `PTR` opaque) and to close the second only when a use turns up. (2)
     `BIT`'s word-based meaning is voc's, against the report's bit of `Mem[a]`,
     and `SYSTEM.NEW` blocks are untraced by the collector: both were chosen
     with voc probed, so the proposal is to record them as decided in
     `AGENTS.md` (they are already described there) and close them.
     **Part (1) done 2026-09-21, decided with the user.** Probed voc (source and
     binary): `p^` and `NEW(p)` on a `PTR` are errors there as well (errs 57,
     111), so `AGENTS.md`'s "unlike voc" was wrong for them; a guard, `IS` or
     `WITH` on a `PTR` is accepted for a record pointer and runs, and for an
     array pointer is accepted but its C does not compile. poc keeps the `PTR`
     opaque: `EmitTagTestOnTag` reads through the block's tag word, which is
     unsound for tag 0 (`SYSTEM.NEW`) or an array descriptor, and supporting
     the record case would need a way to tell those apart. The second half was
     not `PTR`-specific: `a(ArrPtr)[1]`, `a IS ArrPtr` and `WITH a: ArrPtr` on an
     ordinary pointer to an array (the pointer's own type is the only possible
     target, arrays do not extend) all passed the checker - the report's
     "same types" reading - and then failed in the backend, `WITH` compiling
     to a branch that can never be taken (exit 6). voc rejects all three (err
     85). They are a front-end error now (`SemanticActions.IsPointerToNonRecord`,
     used by `CheckGuard`, which serves a designator guard, an argument guard
     and `WITH`, and by `IS`); nothing needs lowering. Fixture
     `semantic-reject-guard-array-pointer`.
     **Part (2) done 2026-09-21, decided with the user.** *`SYSTEM.NEW`*: kept.
     voc's `Heap.NEWBLK` tags the block `NoPtrSntl` - freed when nothing points
     at it, never scanned inside - which is poc's tag 0 (`TraceBlock` returns
     for it); recorded as decided. *`BIT`*: the docs' "voc's word test" was
     true only for `n` below 32. voc's `__BIT(x, n)` is `*(UINT64*)x >> n & 1`,
     a 64-bit read (`n` of 64 or more is a C shift too wide, the hardware
     wrapping it; probed on a buffer of eight `FF` bytes: voc `111111111`,
     poc `111100000` for `n` = 28..36), A2's is a word of address width
     rotated right by `n`, so no dialect answers `FALSE` out of range, and the
     word size differs. The VAX's `BBS`/`BBC` take a *signed* bit position
     relative to bit zero of the byte at the base address (VAX Architecture
     Handbook, 1986: the bit field "specified by ... a base address, a bit
     position" and "the bit position (P) is the signed longword specifying the
     bit displacement ... with respect to bit zero of the byte at address A").
     So `BIT(a, n)` is now that: bit `n` mod 8 of the byte at `a + n DIV 8`
     (floored), defined for every `n`, one byte read. On a little-endian
     machine it is voc's for `n` in 0..63; a big-endian target would differ
     from the word dialects (none is planned). `GenerateBit` is branch-free
     now. Fixtures `llvm-system-shifts` (shared with voc: bits 28..36, 62, 63
     of an eight-byte array) and `llvm-system-extra` (negative `n`, `n` >= 32,
     an `n` of type `HUGEINT` and `SHORTINT`; its old check of `MAX(HUGEINT)`
     as a bit number, which read a wild address under the new meaning, is
     gone).
   - *`HUGESET`.* Under `-O2` a `SET` is 32 bits and a `LONGINT` 32 bits,
     under `-OC` both 64: `SET` follows `LONGINT`. Whether a set as wide as
     `HUGEINT` on every model is wanted is answered from voc's own answer,
     `SYSTEM.SET32`/`SYSTEM.SET64` (voc's; step 7 made `SET32` an alias of
     `SET` and has no `SET64`), which if sufficient means no new predeclared name.
     If so, make them real fixed-width types the way `SYSTEM.INT8..INT64`
     became (Phase 10 step 8: `fixedBytes`, `MemoryLayout`/`LLVMTypes` sizes,
     inclusion by width, `MAX(SET32)`), rather than an alias of `SET`, which is
     32 bits under `-O2` and 64 under `-OC`; `SET32` is then 32 bits under both.
     **Done 2026-09-21, decided with the user.** The premise was wrong: voc's
     `OPM.Mod` (lines 382-385) gives `SET` 4 bytes under `-O2` *and* `-OC`
     (`doc/Features.md`'s 64 for `-OC` is not what the compiler does; probed on
     the binary too), so `SET` is 32 bits under both here (`MemoryLayout.BasicSize`,
     `LLVMTypes.BasicTypeString`; goldens `layout-size-model`, `llvm-types-dump`,
     `module-interface-*` regenerated) and `HUGESET` needs no new name: voc's own
     `SYSTEM.SET64` is adopted, a distinct 8-byte type (`Types.Set64`) with
     elements 0..63. A `SET` is included in it (zero-extended) and not the
     reverse; a mixed operation is at 64 bits. A constant set is typed by its
     value, as an integer constant is (`FoldConstantType`,
     `ConstantEvaluator.SetValueType`; the code generator folds a constant set
     expression to one immediate, `GenerateFoldedInteger`, written as an
     unsigned `u0x` hex for 64 bits so poc's own source needs no 64-bit
     `LONGINT`); a constructor with a variable element is a `SET64` only if a
     constant element is above 31 (`CheckConstantSetElement`,
     `ConstructorSetType`). Where voc is wrong poc is not: voc types a constant
     range as `SET32` and drops its high bits. `ORD` of a `SET64` is a
     `HUGEINT`. Fixtures `semantic-set64`, `llvm-set64` (both models, same
     output), `llvm-set64-import`; the folded constant sets changed
     `llvm-system-ir`'s golden. `AGENTS.md` has what a program can observe.
   - *Initializers on `VAR` declarations.* Decide the syntax and its
     reach: module variables and locals; scalars only or any type; whether
     an exported variable may carry one; how it interacts with the NIL
     default and with a read-only export; the order of evaluation among
     several; and that a `.sym` never carries it. The recommended shape is
     desugaring in the front end into assignments at the start of the
     module body or procedure, so neither backend - including the VAX one
     - changes.
   - *Record and array literals.* The largest design here. Sets already
     have `{...}`, so a literal needs a spelling that does not collide
     with it; it needs a typing rule (typed by its target or by a type
     name in front); it may or may not be a constant; and it needs a
     lowering (a temporary and a copy). Survey what other dialects do and
     decide whether the feature is worth its complexity; dropping it is a
     legitimate result.
   - *Underscores and dollar signs in identifiers.* Wanted for VMS
     (`SYS$QIOW`, `LIB$GET_VM`, `CLI$GET_VALUE`). Note the extension is
     not what makes those routines callable - `["VMS", "SYS$QIOW"]`
     already names the linkage symbol as a string - it only lets the
     Oberon-side name match. Decide whether that is worth a lexer change
     (where each character may appear, whether `$` may start a name), and
     find the consequences in advance: the `.sym` writer, LLVM symbol
     names (LLVM's unquoted identifiers already allow `$` and `_`), the
     31-character mangling of Phase 13 and Phase 15's generated definition
     modules from `STARLET.MLB`. **Decided (user, 2026-09-26): both,
     anywhere a letter may be, first included, since STARLET's values and
     fields (`SS$_NORMAL`, `DSC$W_LENGTH`) are not procedures;
     `-strict` rejects them** (`doc/language-extensions.md`).

7. **An `Err` module.** `rtl/llvm/Err.Mod`, the counterpart of Phase 10's
   `Out`, writing to standard error: the same procedure set, the same
   buffering behavior (decide it: unbuffered is the usual expectation for
   an error stream), through the `Platform` layer written for all four
   Unix-likes. Record it in Phase 12 step 3's inventory as a module poc
   supplies that voc does not. **Testing**: a fixture that writes to both
   streams and checks each goes to its own file descriptor.

8. **Nested procedures.** Lower them in the LLVM backend; the full plan, with
   the design decisions and their reasons, is `doc/nested-procedures.md`. In
   short: they are only ever called by name (`Oberon2.pdf` 6.5 forbids one as a
   procedure value, and the checker enforces it), so none outlives its enclosing
   activation, and **lambda lifting by reference** is enough - each nested
   procedure becomes an ordinary function that takes, as hidden trailing
   parameters, the addresses of the enclosing variables it needs, bound in
   `cg.locals` under the same objects so no designator codegen changes. What a
   procedure needs is a fixed point over the nested call graph (its own uses,
   what its nested procedures need, what the nested procedures it calls need),
   ordered deterministically so the IR is byte-stable for the fixed point, and
   found by *exact* name resolution against the real scope chain (decided
   2026-09-20), not by matching spellings as the `WITH` safety check does: a
   false match there only rejects too much, here it would pair a call with a
   binding that does not exist; a long list of hidden parameters is accepted
   until measured (decided 2026-09-20), the fallback being one pointer to a
   frame record. The
   analysis is a new backend-independent module `NestedProcedures.Mod`
   (`src/front/`, which the VAX backend will reuse) with a `poc -dump-nested`
   mode, so it is golden-tested before any code generation exists. Steps, each
   with fixtures that fail first and a green `make check`: (0) groundwork with
   no behaviour change (`SemanticActions.DeclareLocalProcedures`, a body scope
   passed in rather than opened); (1) the analysis and `-dump-nested`; (2)
   nested procedures that need nothing; (3) hidden parameters for scalars and
   aggregates; (4) `VAR`, `VAR` record (tag), open-array (lengths) and receiver
   variables, and `WITH`; (5) depth, siblings, mutual recursion through a
   forward declaration, recursion of the enclosing procedure; (6) remove the
   error, `AGENTS.md`, both BSD hosts, both word sizes. **Exit gate**: the
   fixtures of the plan's section 6 pass under both compilers, both size
   models, at both word sizes, on Linux, NetBSD amd64 and OpenBSD i386; the
   program that `llvm-reject-nested-procedure` used to reject prints `ok` (it
   is in `llvm-nested-uplevel`); the fixed point still exact; no nested-procedure
   error left in the backend.
   *Progress (2026-09-20):* steps 0 to 5 are done: nested procedures are lowered
   in full (hidden trailing address parameters, with a tag or lengths where the
   variable is a `VAR` record or an open array; step 3 did steps 4 and 5's
   mechanism too), the error is gone, and the fixtures `llvm-nested-basic`,
   `-features`, `-uplevel`, `-params`, `-deep`, `-gc`, `-import` and `-ir` pass
   (the runtime ones also as i686 executables). Step 1 added `NestedProcedures.Mod`
   (also built by `tools/bootstrap/stage0`), `poc -dump-nested`, and six
   `nested-analysis-*` fixtures; poc's own source, which has no nested
   procedure, gives an empty analysis for every file. Left: step 6, `AGENTS.md`
   and the BSD hosts; see `doc/nested-procedures.md` section 5.

9. **Close-out.** `000-todo.org` is brought up to date entry by entry
   (each item `DONE` with a one-line account, or `DROPPED` with the reason;
   the Phase 12 entries left open and marked as such); the "Open design
   questions" section keeps only resolved records, each stating what was
   decided; `AGENTS.md` gets the decisions that change what a poc user
   sees (the same way it records HUGEINT, procedure values and the rest);
   and the BSD runs skipped while the hosts were unreachable are made up:
   the whole conformance suite, at both word sizes, on Linux and at least
   one BSD. **Exit gate**: `make test` clean at both word sizes; the
   Stage 1/Stage 2 fixed point of Phase 10 re-run against the changed
   front end and back end and still exact; every table row above with a
   verdict; and no unlabeled "undecided" left anywhere in `PLAN.md`,
   `AGENTS.md` or `000-todo.org`. **Done 2026-09-26; Phase 11 is closed.**
   `000-todo.org`: every entry `DONE` with its account, or open and marked
   for Phase 12, 13 or 17; every row of `doc/phase-11-inventory.md` has a
   verdict. Gate, on `7831929` (A16 (d), the last code change): `make
   check` (the suite under Stage 0 and Stage 1, the Stage 1/2 fixed point,
   `check-strict`) on atla (Linux x86_64), cymoril (OpenBSD i386, so the
   32-bit word size) and artos (NetBSD amd64), 284/284 each; `make
   check-opt2` (everything at `-O2`) on the same three, fixed point
   included.

**Testing summary**: each decision comes with the voc probe that supports
it, recorded where the decision is; each implemented item has a fixture
that fails before the change and passes after; the step 4 measurement and
the step 5 debugger sessions are fixtures too; step 9's whole-suite run
and the bootstrap fixed point are the gate.
