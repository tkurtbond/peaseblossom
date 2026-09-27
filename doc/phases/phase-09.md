# Phase 9 — LLVM backend, full language parity

Moved here from `PLAN.md` unchanged on 2026-09-25, once the phase was done.
`PLAN.md` keeps the heading, the goal, and a list of the steps, so a reference
elsewhere to "`PLAN.md` Phase 9 step N" means step N here.

**Goal**: every language construct `Oberon2.pdf` defines, compiling and
running correctly through the LLVM backend, on both 32-bit and 64-bit
targets, on Linux and at least one BSD — the point at which the *entire*
conformance suite (not just a hand-picked subset, as Phase 8 step 13
promoted) can compile+link+run+diff. Deliberately *not* the point poc can
compile itself — see Phase 10 (`doc/phases/phase-10.md`) for why self-hosting is a separate,
later gate.

**Explicit non-goals**: `SYSTEM.*` (Appendix C — `ADR`/`VAL`/`BIT`/etc.,
see Phase 10 (`doc/phases/phase-10.md`); a subset, `ADDRESS`/`ADR`/`GET`/`PUT`/`VAL`/`MOVE`, was
pulled forward into Phase 9 step 4) and everything MACRO-32/VAX (Phase 13) are out of
scope per the phase-to-report map, not this phase's; `DISPOSE` isn't
added because it doesn't exist in
`Oberon2.pdf` at all (§10.3's `NEW` has no explicit-free counterpart —
Appendix D3 is explicit that a collector, not the programmer, reclaims
unreachable blocks); `ASSERT` stays whatever `PLAN.md`'s own "No
`ASSERT`" open design question above says when a step below reaches
`PredeclaredProcedures.Mod` lowering — not decided by this plan, and
picking it up is opportunistic, not required for this phase's own exit
gate, unless that question is resolved before then. Also explicitly not
this phase's job, despite being directly downstream of it: any real
`rtl/llvm` module beyond the GC (`Console.Mod`, `Out.Mod`/`In.Mod`,
`Files.Mod`, `Platform.Mod`, `Modules.Mod`, `Strings.Mod`, `Math.Mod`)
and the self-hosting bootstrap itself — both now Phase 10's own scope,
inserted between this phase and the former Phase 10 (VAX/VMS, renumbered
11 and then 12 below) specifically because self-hosting cannot succeed without a
real runtime library first (see Phase 10's own opening for the concrete
dependency: `voc`'s own `Files.Mod` represents an open file as `POINTER
TO FileDesc`, so even a from-scratch `rtl/llvm/Files.Mod` needs this
phase's own `POINTER`/`NEW`/GC work done before it can be written at
all).

**A carried-over gap from Phase 8, not new Phase 9 work but blocking
it**: `LLVMCodeGenerator.Mod`'s `Unsupported` fallback is hit today by
REAL/LONGREAL arithmetic and literals, named STRING constants, and SET
constructors (every one tagged "PLAN.md Phase 8 step 5 scope" in its own
source) — plus ARRAY-OF-CHAR and RECORD relational comparison, which was
never lowered at all (no `memcmp`-equivalent exists). None of these
presuppose `POINTER`/`NEW`/GC the way this phase's headline items do,
but the "entire conformance suite must compile+run+diff" exit gate below
can't be met while they stay `Unsupported` — `semantic-expressions`,
`semantic-const-decls`'s full (untrimmed) form, and others depend on
them. Folded into this phase's build order below (steps 2–3) rather than
left implicit, since Phase 8 step 13 already had to explicitly trim them
back out of two promotion candidates for exactly this reason. (Separately,
`rtl/llvm/Console.Mod` was also never actually built in Phase 8 — every
fixture that needed output declared `PROCEDURE ["C", "write"] SysWrite`
directly instead, Phase 8 step 6's own retrospective explicitly deferring
the real wrapper body to Phase 8 step 10, which shipped ordinary
procedure-with-body codegen but never came back to write it. That gap is
Phase 10's to close, not this phase's — every fixture in the build order
below keeps using the same direct-FFI `SysWrite` pattern Phase 8 already
established, since none of this phase's own new language features need
real formatted I/O to test, only the pass/fail marker every predeclared-
procedure/trap fixture since Phase 8 step 9 already uses.)

**Cross-cutting discipline, not its own step**: every new size-dependent
quantity this phase introduces — pointer width, a type descriptor's own
address width, `ProcTab`/`BaseTypes`/pointer-offset table entry widths,
a dope vector's length-field width — must be parameterized by
`MemoryLayout.Mod`'s existing word-size axis from the moment it's
written, not retrofitted once 32-bit support is checked at the end. This
is the same discipline Phase 4 built `MemoryLayout.Mod` around in the
first place (voc's own `History.md` warning about retrofitting this is
quoted there) and the same axis Phase 8 step 13's real datalayout bug was
found and fixed against — treat that bug as this phase's own cautionary
precedent, not just Phase 8's. The already-separate `-O2`/`-OC`
elementary-size-model axis is unrelated to pointer width and shouldn't
be conflated with it.

**Proposed build order** — each numbered step lands its own conformance
fixtures before the next starts, matching Phase 8's own incremental
style exactly.

1. **Runtime type descriptors (Appendix D5).** `LLVMTypes.Mod` emits one
   type descriptor per record type at run time: a `tag` value (the
   descriptor's own address), a `ProcTab` (bound-procedure addresses,
   indexed by a compile-time-known per-type-bound-procedure index),
   a `BaseTypes` table (one entry per extension level, `BaseTypes[i]` =
   the type descriptor address of the ancestor at extension level `i`,
   used for `v IS T`/type guards as `v^.tag^.BaseTypes[ExtensionLevelT]
   = TypeDescrAdrT`), and a pointer-offset table (byte offsets of every
   pointer-typed field in the record, feeding step 5's collector). Per
   the report's own Fig. D5.1, `ProcTab` and the pointer-offset table
   grow from opposite ends of the descriptor as extension adds more
   procedures/pointers — `RecordType`'s own `baseType`/`methods` chain
   (already fully built by Phase 4/6's front end) gives everything
   needed to compute both an extension level and cumulative
   `ProcTab`/offset-table contents by walking it. Purely static: no
   allocation, no dispatch call, no `NEW` yet — every descriptor is
   emitted as its own LLVM global constant, verified by golden
   `-emit-llvm-ir` diff plus hand-checking one non-trivial extension
   chain's layout against Fig. D5.1's own worked example (the report's
   `Node`/`CenterNode` family — already this project's own go-to fixture
   source, Phase 4/6/8 all having already used it).
   **Testing**: `llvm-type-descriptors-ir`, golden `.ll` diff over a
   base type, a one-level extension, and a two-level extension (to
   confirm growth direction and level numbering, not just presence).

   **Implemented 2026-09-19.** `LLVMCodeGenerator.Mod`'s
   `EmitTypeDescriptors` emits one LLVM constant per module-level record
   type, `@<Module>.<Type>.tdesc`, plus an alias `@<Module>.<Type>.tag`
   for its "tag" (the address a heap block will store and a type test
   will compare) — the section comment above `RecordSymbolBase` is the
   authoritative layout reference. Departures from Fig. D5.1's exact
   picture, all recorded there: every field is one target word wide
   (`iW`, so no padding on any target); `BaseTypes` is exactly
   `level+1` entries long rather than NIL-padded to a maximum depth (so
   `v IS T` must compare `extLevel` first — `v.extLevel >= T.level AND
   v.BaseTypes[T.level] = T's tag` — never read `BaseTypes` unguarded);
   and a three-word header (`size`, `extLevel`, `ptrCount`) sits at the
   tag so the collector can locate the pointer-offset table without a
   maximum extension depth. Pointer offsets are flattened through
   inherited fields, nested records, and fixed arrays (an `ARRAY n OF
   POINTER` contributes `n` entries). Verified against Fig. D5.1 by hand:
   `Node`/`CenterNode` on `i686` give offsets `4, 8` / `4, 8, 16`,
   exactly the figure's. Supporting changes: `Types.RecordTypeDesc` gained
   `moduleName`/`name` (set by `SemanticActions.NameRecordType` for a
   module-level named record, or the anonymous record directly under a
   module-level named `POINTER TO`, called `<pointer name>.base`), because
   a record imported through a `.sym` file is a *different*
   `RecordType` object than its home module built, so a descriptor symbol
   cannot be found by identity across modules; `LLVMTypes.TypeString*` now
   handles a record with a base type (a nested first-element struct,
   which reproduces `MemoryLayout.RecordSize`'s "extension starts after
   the base's whole size" rule exactly) and gives `POINTER`/`PROCEDURE`
   the bare type `ptr` (with `Unsupported`'s placeholder becoming `null`
   for it); `LLVMTypes.ExtensionLevel*/MethodSlotCount*/SlotMethod*/
   MethodSlot*` compute the shape (an override reuses its base's slot).
   Fixtures: `llvm-type-descriptors-ir` (both word sizes, each also
   handed to `clang -c`, since a golden diff alone doesn't prove the IR is
   valid), `llvm-type-descriptors-cross-module-ir`.

   **Known gaps carried forward, not fixed by this step:**
   - **Hidden members** - *resolved by step 4a below (2026-09-19).* A
     `.sym` used to omit unexported record fields and type-bound
     procedures, so a record extending an imported one saw a partial base
     (wrong field offsets, `size`, `ProcTab` slots, and missing hidden
     pointers in the offset table). It now carries them; see step 4a for
     the design, why poc differs from voc's numeric-fact `.sym`, and the
     enforcement that keeps them unreachable by name.
   - **Procedure-local and other anonymous records** get no descriptor
     and no name (`SemanticActions` names only module-level ones;
     `OpenProcedureBodyScope` re-resolves a procedure's local `TYPE`s at
     codegen time, so they aren't even the same `RecordType` objects the
     checker built). Nothing can allocate or test one until steps 5/6, at
     which point either a naming scheme (procedure-qualified) or an
     explicit refusal is needed.
   - **Type-bound procedure bodies** - *resolved by step 6 below
     (2026-09-19).* Each `ProcTab` entry names its symbol
     (`@<Module>.<RecordName>.<ProcName>`); step 1 `declare`d it so the
     IR was valid, and step 6 dropped the declares as it began emitting
     the real `define`s (LLVM rejects a `declare` and `define` of one
     symbol).
   - Unrelated pre-existing front-end quirk seen while writing the
     fixture: `ResolveQualidentType`'s forward-reference check compares
     `obj.declLine >= node.line`, so a type used on the *same source line*
     it is declared on (`Anon = POINTER TO RECORD next: Anon END;`, or
     `A = INTEGER; B = ARRAY 3 OF A;` on one line) is rejected as a
     forward reference. voc accepts it.

2. **REAL/LONGREAL arithmetic, literals, and conversions.** Floating-
   point `EmitBinOp`/`EmitConvert`/`EmitCompare` lowering, replacing the
   REAL/LONGREAL branches of `Unsupported` named above. `-O2`/`-OC`
   don't affect `REAL`/`LONGREAL` width (`PLAN.md`'s own resolved open
   design question already says so), so this is the one area in this
   phase genuinely independent of the word-size/size-model discipline
   above.
   **Testing**: promote (or extend) a runtime fixture exercising
   arithmetic, real division (`/`), `DIV`/`MOD` still integer-only,
   comparisons, and `LONG`/`SHORT` conversions between `REAL`/`LONGREAL`.
   **Implemented 2026-09-19.** Everything above, plus `ENTIER` and the
   integer forms of `LONG`/`SHORT` (the same instructions, a few lines
   more, and `ENTIER` is the only real-to-integer conversion). Outcomes
   worth knowing:
   - **A real numeral is echoed as text, not re-derived from its folded
     value.** `ConstantEvaluator.ParseReal` accumulates error (`0.1`
     is built from a running `scale / 10`), so `Types.Value.realVal` can
     be an ulp off the number the programmer wrote — harmless for
     folding, wrong for emission. `Types.ValueDesc` gained `realText`,
     the numeral's own source text (kept through unary minus by
     `ConstantEvaluator.NegateRealText`, empty for a computed value), and
     `LLVMCodeGenerator.RealConstant` writes that to LLVM's own
     correctly-rounded parser (`D` exponent letter → `e`). Only a
     computed `CONST` (`1.0D0 / 3.0D0`, `-third`) falls back to the folded
     value, emitted as its IEEE-754 bit pattern (`0x…`, built by exact
     power-of-two scaling rather than a bit-cast, which strict
     Oberon2.pdf source has no spelling for).
   - **`REAL` cannot use either obvious spelling in LLVM 22.** A decimal
     `float` literal must be exactly representable in single precision
     (`float 0.1` is "floating point constant invalid for type"), and
     `fptrunc` constant expressions no longer exist. A `REAL` numeral is
     therefore an `fptrunc double <numeral> to float` *instruction* —
     decimal to double to float, a double rounding that differs from a
     direct decimal-to-float conversion only for a numeral within 2^-29
     (relative) of a float midpoint. A computed `REAL` `CONST` is
     rounded to single precision first, then emitted as hex.
   - **Real division is always real**: `7 / 2` is `3.5` (`REAL`), so `/`
     on two integers converts both with `sitofp`; `DIV`/`MOD` stay
     integer-only (the front end already rejects real operands).
   - Comparisons use ordered `fcmp` predicates and `une` for `#`, so
     every relation but `#` is false against a NaN — C's behavior, and
     what voc's generated C does.
   - `ABS` on a real clears the sign bit through bitcast-and-mask rather
     than an `llvm.fabs` call, which would need a `declare` tracked
     program-wide; this also gets `-0.0` right.
   - The new fixtures: `llvm-reals` (56 run-time checks, all with exact
     or deliberately-chosen rounding cases; also cross-checked against
     real voc — see below) and `llvm-reals-ir` (golden `.ll` at both word
     sizes with clang validation, including the bit patterns of a
     subnormal and a large power of two, checked independently).
   - **Three voc quirks found**, recorded in `AGENTS.md`'s "Known voc
     bugs": voc rejects a `LONGREAL` literal that is integral and at
     least 2^31 (`1.0D10`) with "Value out of range"; it constant-folds
     `LONG(SHORT(x))` to `x`; and it prints REAL/LONGREAL constants into
     its generated C with only 8/15 significant digits. The last is why
     three of `llvm-reals`'s checks (27, 44, 51 — exactly the
     single-precision-rounding ones) fail under voc but pass under poc.
   - Still `Unsupported`: `MAX`/`MIN` on `REAL`/`LONGREAL` (also not
     folded by `ConstantEvaluator`), `ASH`, `SIZE`, `INCL`/`EXCL` — step
     8's sweep.

3. **SET constructors/operators, named STRING constants, and
   ARRAY-OF-CHAR/RECORD relational comparison.** The remaining
   `Unsupported` fallbacks named above: `{...}` SET constructor codegen
   (element/range list to bitmask), a named STRING `CONST`'s own value
   (`GenerateConstValue`'s `stringValue` branch — distinct from a
   literal passed directly to a call, already handled since Phase 8 step
   11), and `=`/`#`/`<`/`<=` over `ARRAY OF CHAR` and record-field-wise
   equality where the front end already permits it. Once this and step
   2 land, revisit Phase 8 step 13's own trimmed `llvm-const-decls`/
   `crosscheck` pair and the fixtures it explicitly passed over
   (`semantic-expressions`, the untrimmed `semantic-const-decls`) — some
   should now promote cleanly without trimming.
   **Testing**: a SET-operations fixture, a named-string-CONST fixture,
   an ARRAY-OF-CHAR-comparison fixture; re-run the Phase 8 step 13
   promotion survey and land whichever candidates are now unblocked.
   **Implemented 2026-09-19.** All of the above, plus `IN` and
   `INCL`/`EXCL` (which `PLAN.md` step 8 had earmarked for its sweep, but
   are SET operators no less than the constructor is), and assignment of
   a string to a `CHAR` array. Outcomes worth knowing:
   - **`IN` was not lowered at all** before this step - not just for
     sets built from constructors: `GenerateBinaryExpr` had no branch
     for it, so it fell to "unrecognized binary operator". `x IN s`
     checks `0 <= x < width` at x's own width first (an unsigned
     compare, so a negative x fails too) and `select`s the shift's
     result away when it does not hold, giving "not in the set" for an
     out-of-range element instead of an LLVM poison value (Oberon2.pdf
     leaves it undefined; voc's C shifts and inherits C's undefined
     behavior). A `select` rather than an `and`, since `and` would itself
     be poisoned.
   - **A SET constructor** is the OR of one mask per element: `1 shl e`,
     or, for a range `lo..hi`, `(-1 shl lo) and (-1 lshr (W-1-hi))`, which
     is empty by itself when lo > hi. Elements are converted to the SET's
     width first (`sext`/`trunc`) - an element may be any integer type,
     including `HUGEINT` under `-O2`'s 32-bit SET - and need not be
     constant.
   - **The AST has no resolved types**, so whether an operand is a
     character sequence has to be decided before it is generated:
     `DesignatorStaticType`/`IsCharSequenceExpr` walk the declarations
     without emitting anything, and `GenerateBinaryExpr` picks the whole
     lowering from that. (`GenerateDesignatorValue` for an array still
     loads the aggregate, which whole-array assignment relies on; a
     character sequence is instead used by address plus a compile-time
     length, never as a loaded value.)
   - **Character-sequence comparison** is one call to a private
     `@.charcmp` helper (three-way, unsigned bytes, a sequence ends at
     its first `0X` *or* at the end of its array). `COPY` from a
     non-literal source calls `@.charcopy`; from a string or named
     constant it stays the unrolled byte stores it always was, now shared
     with assignment (`EmitStringStores`). Both helpers, and the string
     globals, are emitted *at the end of the program and only if used*
     (`Codegen.needCharCompare`/`needCharCopy`/`pendingStrings`), so
     every earlier golden `.ll` stayed byte-identical.
   - **A named STRING `CONST` has no storage**, so its text becomes a
     private global on first use, deduplicated by content
     (`@.strconst.N`, `StringConstGlobal`) - by content rather than by
     position because an imported constant's position in a regenerated
     `.sym` bears no relation to its home module's. A one-character
     string, literal or named, in a *scalar* position (`ch := "x"`,
     `ch = "x"`, a `CHAR` argument) is a `CHAR` immediate, which also
     closes the gap `llvm-predeclared`'s header comment documents.
   - **Records:** `Oberon2.pdf` has no record comparison and the front
     end (correctly) rejects it, so there is nothing to lower - the
     "record-field-wise equality" in this step's own text was a
     misreading of "where the front end already permits it".
   - **Still not done**, for later steps: a character sequence behind a
     pointer or in a record with a base type (steps 5-6 - the address
     cannot be computed yet), and an *open* `ARRAY OF CHAR` operand or
     parameter (step 7's dope vectors) - either falls back to the same
     `; unsupported` placeholder as before. (All three done by steps 5-7.)
   - **Two voc differences found**: voc rejects a *constant* SET range
     with lo > hi at compile time (`{5 .. 2}`), which poc's front end
     does not, so the fixture uses a non-constant one; and voc's
     character-array comparison scans past the end of an array with no
     `0X` in it (undefined), where poc stops at the array's end - the one
     check of `llvm-char-arrays` (21) that fails under voc, everything
     else in it and all of `llvm-string-consts` agree.
   - **Fixtures** (127 tests pass): `llvm-sets` (35 checks; 32 also under
     voc), `llvm-string-consts` (two modules, identical output under
     voc), `llvm-char-arrays` (43 checks), `llvm-sets-strings-ir`
     (golden `.ll` at both word sizes, clang-validated, including both
     helper functions). **Promotion survey redone:** `llvm-const-decls`
     and `crosscheck` regained everything Phase 8 step 13 trimmed
     (`pi`/`widened`/`half`, `greeting`, `aSet`/`combinedSet`/
     `isMember`) - the CONST section is now `semantic-const-decls`'s own,
     complete, and voc and poc still both print `OK`; and
     `semantic-expressions` is promoted as `llvm-expressions-supported`
     (not run - its VARs are never assigned, so `i DIV j` would divide
     by zero - but every expression in it now lowers with no
     `; unsupported` marker, and clang accepts the IR).

4. **Bespoke mark-sweep GC (`rtl/llvm/GarbageCollectedHeap.Mod`,
   `ModuleTable.Mod`).** A bump-allocating heap plus a mark-sweep
   collector (the locked-in decision: no external C allocator/collector
   dependency), using step 1's pointer-offset tables to trace a live
   record's own outgoing pointers during mark, and a whole-program root
   set assembled from every loaded module's global pointer-typed `VAR`s
   — `ModuleTable.Mod` is the registry each module's init function
   registers itself into (mirroring voc's own module-table precedent
   named in `PLAN.md`'s directory layout), and `LLVMCodeGenerator.Mod`
   gains its own per-module "which globals are GC roots, and at what
   offsets" table generation, the module-scope analogue of step 1's
   per-record one. Written as genuine Oberon-2 source, tested via the
   same direct-FFI `SysWrite` pattern every Phase 8 fixture already
   uses (Phase 10's own step 1 is what proves a *poc-compiled* rtl
   module can be `IMPORT`ed and run — this step doesn't need that
   machinery yet, only a working allocator/collector any fixture under
   test can call into directly). Collection can be purely allocation-
   triggered (no separate `SYSTEM`-level manual trigger — nothing in
   `Oberon2.pdf` exposes one); no compaction, no generations, no
   finalization — matching the "bespoke mark-sweep... no external C
   dependency" decision's own evident scope, nothing fancier.
   **Testing**: a standalone allocation/collection stress fixture
   (allocate many short-lived records in a loop, confirm memory is
   actually reclaimed — e.g. via a `SYSTEM`-free observable proxy like
   allocation count vs. a small fixed heap ceiling, not raw RSS).

   **Revised design (2026-09-19, decided with the user).** Two things in
   the text above do not survive contact with the code, and a third was
   missing:
   1. *"Genuine Oberon-2 source" needs raw memory access, and the only
      spelling of that in `Oberon2.pdf` is `SYSTEM` (Appendix C) - which
      Phase 10 step 7 schedules after this step, while `POINTER`/`NEW`/
      dereference codegen is step 5.* Resolved by **pulling a `SYSTEM`
      subset forward into this step**: the pseudo-module itself,
      `SYSTEM.ADDRESS`, `ADR`, `GET`, `PUT`, `VAL`, `MOVE`. Phase 10
      step 7 keeps the rest (`BYTE`, `PTR`, `BIT`, `LSH`, `ROT`,
      `SYSTEM.NEW`) and its own fixtures; nothing there changes except
      that it starts from a working front-end/back-end foundation.
      `SYSTEM.ADDRESS` is an integer type of *target word width*, ranked
      between `LONGINT` and `HUGEINT` in the numeric hierarchy.
   2. *The plan's root set (module-level pointer `VAR`s) omits the
      stack.* A pointer held only in a procedure's local or parameter is
      just as live, and a collector that misses it frees objects out
      from under running code. Poc has no stack maps, so the collector
      scans the stack **conservatively** (any word that points into a
      heap block keeps that block alive), the same approach voc's own
      `Heap.Mod` takes. Registers are spilled by a `setjmp` in the
      collector; the stack base is recorded by the program's `main`
      (`llvm.frameaddress`), which is the outermost frame anything can
      live in. Heap objects and module globals stay *precise* (step 1's
      pointer-offset tables and the new per-module root tables).
   3. *`ModuleTable` is a registry, not a module the program always
      has.* A program pays for none of this unless it imports
      `GarbageCollectedHeap`/`ModuleTable` (explicitly for now - step 5's
      `NEW` lowering adds the import implicitly): the backend emits each
      module's root table and its registration call only when
      `ModuleTable` is in the program.
   Heap shape: chunks obtained from libc (`calloc`, the one OS-facing
   dependency, declared through the existing FFI), each carved into
   16-byte-granule blocks laid out `[size|mark word][tag word][data]`;
   bump allocation within the current chunk, a first-fit free list of
   swept blocks ahead of it, collection when both fail, then a new
   chunk (up to a settable ceiling, so a fixture can prove reclamation
   against a small fixed heap). A per-chunk bitmap of block starts makes
   the conservative scan able to ask "is this word inside a block, and
   which". Marking is iterative with an explicit mark stack (deep lists
   cannot overflow the machine stack), falling back to a heap rescan if
   the mark stack itself overflows. No compaction, generations or
   finalization, as above.

   **Implemented 2026-09-19.** Everything above, with these departures
   and findings (`rtl/llvm/GarbageCollectedHeap.Mod`, `ModuleTable.Mod`;
   the `SYSTEM` subset; per-module root tables in `LLVMCodeGenerator.Mod`):
   - **`SYSTEM` subset.** `SYSTEM` is a pseudo-module with no source or
     `.sym`: `SymbolTable.SystemScope` holds `ADDRESS`, `ADR`, `GET`,
     `PUT`, `VAL`, `MOVE` (all exported), and `ResolveImport` binds
     `IMPORT SYSTEM` (or an alias) straight to it - the whole-program
     walks in `Poc.Mod` skip the name. The procedures reuse
     `PredeclaredProcedures.CheckCall`'s by-name dispatch (no predeclared
     name collides with them, so a qualified `SYSTEM.ADR(x)` needs nothing
     else; the `.sym` writer prints `SYSTEM.ADDRESS` through its ordinary
     imported-type lookup). **`Types.Address`** is a distinct integer type,
     rank between `LONGINT` and `HUGEINT` (`hugeIntRank`/`realRank`/
     `longRealRank` moved up one): a `LONGINT` may be assigned to an
     address, not the reverse - unlike voc, where it is `LONGINT`'s
     alias. Its width is the target word (`LLVMTypes` reads
     `ConstantEvaluator.wordSize`, `MemoryLayout.BasicSize` takes it as a
     parameter now); `ExtendTo` gained the `trunc` case for the one shape
     where the included type is *wider* (`-OC`'s 64-bit `LONGINT` on a
     32-bit target). Lowering: `ADR` = `ptrtoint` of the designator's
     address (so, for now, only designators `GenerateDesignatorAddress`
     can address - no pointer dereference until step 5), `GET`/`PUT` =
     `inttoptr` + a load/store **`align 1`** (an address has no alignment
     requirement in the report), `VAL(T, x)` = `ptrtoint`/real bitcast to
     an integer, `sext`/`zext`/`trunc` to `T`'s width, then `inttoptr`/
     bitcast (defined by poc for differing widths, where the report and
     voc leave it undefined), `MOVE` = `llvm.memmove` (declared once, at
     the end, only if used; a negative count moves nothing). `SIZE(T)`,
     which no earlier step had lowered, came along: it is a constant.
     Phase 10 step 7 has since done the rest, bar `GETREG`/`PUTREG`/`CC`
     and `SET64`.
   - **Register spilling is `llvm.eh.unwind.init`, not `setjmp`.** It is
     declared as an ordinary external procedure
     (`PROCEDURE ["C", "llvm.eh.unwind.init"] SpillRegisters;` - LLVM
     symbol names may contain dots), needs no libc, no `returns_twice`
     attribute, and cannot hide a pointer behind glibc's pointer-mangling of
     the saved registers. `Collect` calls it, then a *deeper* procedure
     (`MarkFromStack`) takes the address of one of its own locals as the
     top of the range to scan, so the spill slots sit inside it.
   - **The start map is one byte per granule**, not one bit: no bit
     operations to write (poc's `SET` is 32/64 bits and `ASH`/`LSH` are not
     lowered), for 1/16 of the block area. **Object size lives in the
     block header** (`size * 4 + inUse * 2 + marked`), and a tag describes
     *one element* - an object of several elements (an array of records)
     is traced element by element, `dataSize DIV size` of them, so step 5
     can give an array of pointers or of records the element type's
     descriptor; tag 0 = no pointers. The mark-stack overflow fallback is
     "re-trace every marked block until a pass does not overflow", rather
     than a per-block "scanned" bit the header has no room for on a 32-bit
     target.
   - **Root tables and the stack base are generated only when the
     program contains the module**: `@.roots.<Module>` (`{ next, count,
     slots }`, slot = address of a pointer location, flattened by the same
     `EmitPointerOffsets` the descriptors use, now taking an optional
     global symbol) is emitted, and registered at the top of `<Module>_init`,
     only if `ModuleTable` is in the program; `main` calls
     `GarbageCollectedHeap.SetStackBase(llvm.frameaddress(0))` only if
     `GarbageCollectedHeap` is. A program using neither has byte-identical
     output to before (every earlier golden held).
   - **No `NEW` yet, so the fixtures build descriptors by hand.** There
     is no source-level way to name a record's `.tag` (`SYSTEM.TYP` is not
     in Appendix C), so `llvm-gc-*` lay a descriptor out in a global array
     in the layout the section above `RecordSymbolBase` documents and pass
     its address to `Allocate`; objects are read and written through
     `SYSTEM.GET/PUT`. That layout is the *contract* the collector reads,
     and step 5's `NEW` is what first exercises it against a compiler-
     emitted descriptor - keep that in mind when it lands.
   - **Conservative scanning means false retention is possible, and the
     fixtures are written around it**: a stale stack slot can keep one
     dead object (and, precisely traced, whatever it points to) alive, so
     nothing asserts that a *specific* dead object is gone - only
     aggregate reclamation (a ceiling of 64 KB never exceeded while 3 MB
     are allocated, `LiveBytes` back near zero) and that live objects
     survive.
   - **Three things found and fixed on the way.** (1) `EmitIndexRangeCheck`
     compared a narrow index against the array length *in the index's own
     type*: a constant index is typed by its value, so `a[99]` is an `i8`
     and `icmp slt i8 99, 1024` reads the 1024 as 0 - every in-range access
     to such an array by a small constant trapped. It now widens first
     (`llvm-narrow-index`). (2) `ModuleInterface.ReadModuleSource` now
     tries `<Module>.Mod` after `<Module>.mod`, so the runtime library keeps
     the repository's spelling. (3) `Poc.Mod`'s whole-program walks skip
     `SYSTEM`. **Not fixed, found**: `SHORT` rejects a `HUGEINT` argument
     (`PredeclaredProcedures.CheckShort` lists only `LONGINT`/`INTEGER`/
     `LONGREAL`); open-array *parameters* still cannot be indexed or
     passed on (step 7's dope vectors, since built), which is why the
     collector and its fixtures pass only fixed arrays and scalars.
   - **Limits, recorded in the collector's own header:** one object at
     most 2^27 bytes; a chunk must not straddle the 32-bit signed
     boundary (address tests are offsets from the chunk start otherwise);
     chunks are never returned; no `free`. **32-bit verification
     (2026-09-19, after `glibc-devel.i686` was installed):** `llvm-i686-
     runtime` builds every runtime fixture (Phase 8's, steps 2-3's and
     both collector fixtures) as a real `i686-unknown-linux-gnu` ELF,
     runs it, and requires the output to equal its 64-bit sibling's
     `expected`; it skips itself (still passing, with a `SKIPPED` line)
     where `testenv.sh`'s `i686_can_run` finds no runnable 32-bit x86
     runtime. All 14 agree. It also found that `-target ... -build` had
     been linking for the *host*: `LLVMToolchainDriver.Build` never passed
     `--target` to `clang`, which merely warns about a module whose
     triple differs - fixed. `llvm-system`'s check 21 had assumed a
     64-bit address; it now compares against `SIZE` of a pointer.
   - **Fixtures** (133 tests pass): `llvm-system` (34 checks, 32 also
     under voc at `-O2` and `-OC`; two poc-only checks for `VAL` between
     widths), `llvm-system-ir` (golden at both word sizes, clang-checked),
     `llvm-gc-collect` (roots: plain/array/record; stack: local and interior
     pointer; reclamation against a ceiling; the ceiling stopping a program
     that keeps everything), `llvm-gc-tracing` (a 100-way fan-out against a
     4-entry mark stack, an object of four record elements, an object bigger
     than a chunk, coalescing of dead neighbours), `llvm-gc-roots-ir`
     (golden root table + `main`'s stack-base call at both word sizes),
     `llvm-narrow-index`. Disabling the stack scan, the
     module-table scan or the overflow fallback in a scratch copy of the
     collector makes the fixtures fail (the last, and the stack scan's
     knock-on damage, by hanging in a loop over a corrupted heap - there is
     no timeout in `poc_build_run`).

4a. **Hidden members in `.sym` files.** *(Numbered "4a" rather than
   renumbering steps 5–9, whose numbers are cited from source comments
   and from `PLAN.md`; it has no dependency on steps 2–4 and can land
   any time before step 5 — `NEW` needs a correct `size` for an imported
   base, and step 6's dispatch needs correct `ProcTab` slots. Found by
   step 1's cross-module work; decided with the user 2026-09-19.)*
   **The problem.** `ModuleInterface.Mod`'s writer prints only exported
   fields and exported type-bound procedures, so a module extending an
   *imported* record sees a partial base: missing fields shift the
   extension's own field offsets and its `size`; missing type-bound
   procedures shift the `ProcTab` slots its own new procedures get and
   under-count `MethodSlotCount(base)`. Any pointer-typed hidden field is
   also missing from the extension's descriptor offset table, which the
   step 4 collector would then fail to trace. (The base's own `.tag`
   symbol is unaffected — step 1 made that immune on purpose — but
   everything derived from the base's *shape* is wrong.)

   **What voc does, and why poc deliberately differs.** Checked against
   voc's own exporter (`OPT.Mod`'s `OutStr`/`OutFlds`/`OutHdFld`/
   `OutTProcs`, and `OPM.Mod`'s `ExpHdPtrFld = TRUE`, `ExpHdProcFld =
   FALSE`, `ExpHdTProc = FALSE`, `MaxHdFld = 2048`): voc does not export
   hidden members as declarations at all. Its binary `.sym` stores the
   record's computed `size`, `align`, and method-slot count `n`, each
   exported field with its numeric byte offset, each exported
   type-bound procedure with its explicit method number, and — the one
   hidden thing it does export — an anonymous `@ptr` entry (offset only)
   per hidden pointer, flattened through hidden nested records/arrays,
   for the importer's own descriptor. So `showdef` shows only the
   exported part because the format never held more, not because it
   filters; the compiler reads *computed layout facts*, not the hidden
   declarations. Those facts bake in a target: voc ships separate
   `2/sym` and `C/sym` trees per size model for exactly this reason. Poc
   wants one target-independent `.sym` usable at both word sizes and
   both size models (a stated Phase 4/8/9 goal), and Phase 7 decided
   `.sym` is valid Peaseblossom module source. Both are preserved by
   carrying the hidden *declarations* and letting the importer compute
   layout with `MemoryLayout` at its own target — the home module and
   every importer then use one algorithm and cannot disagree. Rejected:
   numeric-fact `.sym` (needs per-target files plus syntax the parser
   doesn't have), and a binary `.sym` (gives up "`.sym` is source", needs
   a separate dump tool, buys nothing this design lacks).

   **Design.**
   1. *Writer (`ModuleInterface.Mod`)*: print **every** field of every
      printed record type, in declaration order (layout depends on it) —
      exported ones with their `*`/`-` mark exactly as today, unexported
      ones as bare `name: T`. Likewise every type-bound procedure of every
      printed record type, in declaration order (slot numbering depends on
      it), unexported ones without a mark and still as permanently
      body-less `PROCEDURE^` forward declarations with their real
      signatures. `PrintMethods`' current gate (the receiver's own type
      identifier must be exported) goes away for methods of any record
      type that gets printed.
   2. *Unexported types the hidden members need*: print, as ordinary
      unexported `TYPE` declarations, every unexported named type
      reachable (transitively — a fixpoint, not one level) from a printed
      record's field types or a printed method's signature, in their
      original relative declaration order (so a definition precedes its
      uses exactly as in the source, and §4 rule 3's forward-`POINTER`
      exception still applies). Reachable-only, not "all private types":
      keeps `.sym` minimal and never drags in an unexported type nothing
      exported depends on. This replaces `FindInScope`'s
      `requireExported` structural-inline fallback for those cases — that
      fallback prints an unexported record *inline*, which would give two
      uses of one type two distinct anonymous `RecordType`s in the
      importer, breaking type identity; a named unexported declaration
      preserves it. It also preserves step 1's descriptor naming, since
      `Types.RecordTypeDesc.name` derives from the *declared* name, which
      must therefore round-trip through `.sym` unchanged. Types a hidden
      member takes from a third module need nothing new: the existing
      unconditional re-export of every import already covers them (what
      was an "occasional harmless extra import" is now load-bearing —
      update that comment).
   3. *Restore the export invariant on the reading side.*
      `SymbolTable.ObjectDesc.moduleScope`'s documented invariant —
      "holds exactly the exported members, so no separate export check is
      needed" — no longer holds. Every site that relied on it needs an
      explicit rule: (a) `SemanticActions.FindQualified` rejects an
      unexported object with a "not exported by module" diagnostic
      (`semantic-reject-not-exported` currently passes only because the
      name is *absent*, so its expected message changes); (b)
      `ModuleInterface.FindInScope` on an *imported* scope now needs
      `requireExported` too (its own comment currently says an imported
      scope is exported "by construction"); (c) field selection and
      type-bound-procedure calls across modules reject an unexported
      member unless `IsLocalType` says the record is local — the same
      helper the `-` read-only rule already uses (`CheckDesignator`'s
      `field.readOnly & ~IsLocalType(...)`); an unexported *method* needs
      the same gate in its own lookup path; (d) the backend's
      `ResolveQualifiedObject` runs only after the checker passed, so it
      needs no change, but its comment should stop claiming the scope is
      exported-only.
   4. *A stale `.sym` is now a correctness bug, not just a type-check
      one.* `-build`/`-emit-llvm-ir` type-check a module against its
      imports' *existing* `.sym` files (`ResolveImport`) but compile each
      import from its *real source* (`DiscoverModule`) — so an
      out-of-date `.sym` would give the importer's codegen a different
      record layout than the imported module's own. Fix: in the
      whole-program commands, regenerate `<Import>.sym` from real source
      for every transitive import that has source (post-order, before the
      importer is checked; into `-output-dir`, which lookup already
      consults ahead of the import path only via cwd, so verify that
      precedence when implementing) and fall back to a bare pre-existing
      `.sym` only for a source-less imported module. This also retires the
      "run `poc -emit-interface lib.mod` first" step every multi-module
      fixture currently repeats by hand. voc's answer to the same hazard
      is fingerprints (`pvfp` etc.); regenerating from source is simpler
      and is enough while every whole-program build has the source.
   5. *Optional, not a gate*: a `-show-interface` (stdout, exported view
      only) mode — the `showdef` analogue — by threading an
      `includeHidden` flag through the same writer. Cheap once the writer
      distinguishes the two; skip if it costs more than that.

   **Open questions to settle against `Oberon2.pdf`/real voc while
   implementing** (each becomes a fixture either way): (i) may an
   extension in another module declare a field or type-bound procedure
   whose name equals a *hidden* base member's? `Types.AddField` doesn't
   check inherited names today, and until now an importer couldn't even
   see the base's hidden ones; (ii) hidden-and-overriding type-bound
   procedures — voc reports its error 109 for one it "did not detect in
   OPP because record exported indirectly or via aliasing", so there is a
   real rule to match; (iii) whether an unexported type reachable only
   from a hidden member must itself avoid clashing with an importer's own
   declaration of that name — it must not, since it is never visible
   unqualified, but confirm `Insert`'s duplicate check is only ever run
   against the importer's own scope, not `moduleScope`.

   **Testing.** `module-interface-hidden-write` (golden `.sym`: a hidden
   field, a hidden pointer field, a hidden type-bound procedure, an
   unexported type reachable only through a hidden field, and one
   unreachable unexported type that must *not* appear); `semantic-reject-
   hidden-field-access`, `semantic-reject-hidden-method-call`,
   `semantic-reject-qualified-unexported-type` (plus the updated
   `semantic-reject-not-exported`); `module-hidden-extension-layout` (an
   importer extends a base with hidden members; its `SIZE`/`-dump-layout`
   view of the base equals the base's own, at both word sizes and both
   size models); `llvm-type-descriptors-hidden-members-ir` (cross-module
   golden `.ll`, extending step 1's `llvm-type-descriptors-cross-module-
   ir`: the importer's descriptor `size`, pointer-offset table including
   the hidden pointer, and `ProcTab` slot numbering all match the base's
   own, `clang -c`-validated); `module-hidden-roundtrip` (`-emit-interface`
   twice, the second time on the first's own `.sym`, byte-identical — the
   same technique `module-interface-real-roundtrip` uses); and
   `module-rebuild-stale-sym` (edit a hidden field in the library
   *without* re-emitting its `.sym`; `-build` must still lay the importer
   out against the new field). **On landing**, update: `PLAN.md`'s step 1
   "Known gaps" bullet (remove it), `AGENTS.md`'s Phase 7 paragraph
   ("exported declarations only" is no longer true) and — a stale fact
   found while researching this — its voc source path, which says
   `/usr/local/sw/src/lang/Oberon/vishap/voc` but is actually
   `.../vishap/compiler`; `ModuleInterface.Mod`'s and
   `SymbolTable.Mod`'s header comments; `FindQualified`'s comment.

   **Implemented 2026-09-19.** Design as above, with these outcomes and
   deviations:
   - *Writer*: `ModuleInterface.Write*` runs its whole declaration-printing
     pass to a fixpoint with output suppressed (`dryRun`; `WriteStr`/
     `WriteLn` write nothing), collecting unexported types into a
     `NeededType` list (`NeedType`), then once for real - so marking and
     printing share `FindBoundName`/`FindOwnBound` by construction instead
     of a second, separate "mark" walker. Reachable types now include
     those referenced by exported `VAR`s and free-procedure signatures
     too, not only by hidden members, so an unexported record reached
     through an exported pointer (the `Tree`/`Node` idiom) is printed as a
     *named* unexported declaration instead of inline. That also fixes a
     step 1 mismatch: the inline form gave the importer's record the name
     `Tree.base` while the home module's was `Node`, i.e. two different
     descriptor symbols for one type. A name is only usable inside a TYPE
     declaration if declared earlier (or is the declaration's own name), or
     - a POINTER declaration's own direct base only - later (§4 rule 3);
     a predeclared basic type is always spelled by its Universe name. The
     former rule-free lookup also had a latent bug, fixed by this: two
     exported names sharing one type printed as the cyclic `A* = B;
     B* = A;`. Unexported types' own procedures travel with them; an
     unexported receiver type is printed too, so exported methods on it
     now reach importers (they used to be dropped).
   - *Reader*: `FindQualified` rejects an unexported object; a new
     `lookupDiagnosed` flag stops callers piling "undeclared identifier"
     on top of an already-reported "not exported"/"not an imported module"
     (`semantic-reject-import-not-on-path` lost that redundant second
     error). Field and type-bound-procedure selection judge the record that
     *declared* the member (`Types.FieldOwner`/`MethodOwner`), and locality
     is `rec.moduleName = currentModuleName` (`IsLocalRecord`; every
     `RecordType` is now stamped with its declaring module, named or not),
     which **replaces `IsLocalType`** and closes both its known loopholes
     (a local alias of an imported record; an anonymous record under a
     local pointer). The read-only `-` rule now uses the same owner-based
     test, so a local extension no longer makes an imported base's
     read-only field writable. An unexported CONST/VAR/PROCEDURE is still
     just absent from a `.sym` ("undeclared identifier"); only hidden
     types/members give the new "not exported" wording.
   - *Open questions, settled against real voc (probed 2026-09-19)*: (i) an
     extension may declare a field named like a hidden base field - two
     distinct fields; (ii) it may declare a type-bound procedure named like
     a hidden base one, any signature - a *new* procedure in its own slot,
     not an override, and no clash; (iii) an importer's own declarations
     never collide with a `.sym`'s hidden type names (`Insert` only ever
     runs against the importer's own scope). So hidden members count for
     layout and slot numbering but are invisible to name resolution and to
     overriding: `Types.FindOverridable` (exported, or declared by a record
     of the same module) decides what a declaration can override, and both
     the checker's `CheckOverride` and `LLVMTypes`' slot numbering use it,
     so they cannot disagree.
   - *Stale `.sym`*: `Poc.Mod`'s `RegenerateInterfaces` regenerates each
     transitive import's `.sym` from real source, post-order, before the
     top module is checked, for `-emit-llvm-ir` and `-build`; a source-less
     import keeps its existing `.sym`. Output goes to `-output-dir` (cwd by
     default) and `ModuleInterface.SetInterfaceDir` makes `ReadSource*` look
     there *first*, so a stale copy elsewhere cannot shadow a fresh one -
     this settled the precedence question flagged above. Fixtures for the
     whole-program path no longer hand-run `poc -emit-interface` for
     imports (older fixtures still do, harmlessly).
   - *Two further latent bugs* found while testing, both fixed:
     `ResolveProcDecls` used `FindMethod` (which walks the base chain) to
     decide whether a procedure body completes a forward declaration, so an
     override of an *imported* method found the base's `.sym`-loaded,
     permanently pending method and mutated it instead of recording the
     override (`Types.FindOwnMethod` now); and a function returning a
     pointer emitted the invalid placeholder `ret ptr 0` (now `null`, in
     both `GenerateProcedureDecl` and `GenerateReturnStatement`, alongside
     `Unsupported`'s).
   - *Fixtures* (names differ slightly from the plan above):
     `module-hidden-members` (golden `.sym` incl. transitive types, a
     third-module type, an unreachable type that must not appear, the
     alias fix; `.sym` round trip; importer/home layout agreement at all
     four word-size x size-model combinations), `semantic-reject-hidden-
     members` (hidden field, hidden method, unexported qualified type,
     hidden field through a local extension, plus the exported field of the
     same extension as the accepting control), `llvm-type-descriptors-
     hidden-members-ir` (cross-module golden `.ll` at both word sizes,
     `clang -c`-validated: the importer's size, pointer offsets including
     the hidden pointer, and `ProcTab` slots incl. a same-named new
     procedure beside the hidden one), `module-rebuild-stale-sym` (edits a
     hidden 8-byte field without re-emitting `.sym`; sized so a stale view
     would visibly disagree), and updated goldens for `module-interface-
     write` and `semantic-reject-import-not-on-path`.
   - *Not done*: the optional exported-view-only `-show-interface` mode -
     the writer would need only an `includeHidden` flag, but nothing needs
     it yet. `AGENTS.md`, `SymbolTable.Mod`'s header, `ModuleInterface.Mod`'s
     header, and the `FindQualified` comments are updated; the stale voc
     source path in `AGENTS.md` is fixed.

5. **`NEW` (fixed record/array), `POINTER`, `NIL`, `^` dereference,
   `IS`/type guards, and the `WITH` pointer guard.** `NEW(v)` lowers to
   step 4's allocator plus writing `v^`'s tag from step 1's descriptor;
   `v^.field`/`v^[i]` dereference through the allocated block (NIL-
   checked and trapped before every dereference — matching voc's own
   `-p` pointer-check convention, referenced but explicitly out of
   scope in Phase 8 step 9's own retrospective "NIL-dereference
   trapping... doesn't apply yet since there are no pointers in scope" —
   it applies now); `v IS T`/`v(T)` lower to the `BaseTypes` check
   step 1's own descriptors exist for. `GenerateStatement`'s own dormant
   `WITH` fallback and `RETURN`'s `s.value # NIL` arm (both flagged
   "until Phase 9/10 make it reachable" in Phase 8 step 7's
   retrospective) become real here. First step where a fixture can
   allocate, mutate, and observe a real heap-resident data structure.
   **Testing**: a linked-structure fixture (a small self-referential
   record chain — the report's own `Node`/list-building style examples
   are the natural source), a `NIL`-dereference trap fixture (matching
   the existing index-range/CASE trap fixtures' own pattern), a type-
   guard/`IS` fixture, and a real `WITH` fixture (abandoned as
   impossible in Phase 8 step 7, now buildable).

   **Implemented 2026-09-19.** Everything above, with these outcomes and
   departures:
   - *Dereference*: `GenerateDesignatorAddress` walks `.`/`[`/`^`/`v(T)`
     through pointers - `.`/`[` on a pointer load it, NIL-check it and
     continue from what it points to; `^` does the same explicitly; a
     field inherited from a base record is reached through one "element
     0" GEP per extension level (`GenerateFieldAddress`), an own field's
     struct index being one more than its declaration position when the
     record has a base. `DesignatorStaticType` mirrors it (and a WITH-
     narrowed variable, `Codegen.narrowings`). A NIL check is a compare and
     a branch to a trap: `nilderef` (exit 4). The trap-message globals for
     NIL/guard/WITH (exits 4/5/6) are emitted lazily, like
     step 3's helpers, so programs without pointers keep byte-identical IR.
     Pointer `=`/`#` needed nothing new (`icmp` on `ptr`); `NIL` is `null`.
   - *`NEW`*: `GenerateNew` for a pointer to a record or to a fixed array
     calls `GarbageCollectedHeap.Allocate(size, tag)` (tag = the record's
     `.tag` alias; for an array, 0 when its elements hold no pointers, else
     a synthesized `@.arraydesc.<n>` - the record-descriptor layout with
     size = ONE ELEMENT and no ProcTab, which is what the collector's
     "elements = dataSize DIV size" rule wants) and stores the result
     as the pointer - a 0 result (heap exhausted) becomes NIL, with no
     trap, exactly as voc's `NEWREC` does (an earlier draft trapped with
     exit 7; the report is silent, so voc's behavior wins). The next
     dereference of the NIL then traps like any other. `NEW` of an open
     array was step 7's (`; unsupported` until then). **The runtime is linked in implicitly**: a source
     module never imports `GarbageCollectedHeap`/`ModuleTable` for `NEW`,
     so `PredeclaredProcedures.NewWasCalled` (a process-lifetime flag set
     by `CheckNew`) tells `Poc.AddRuntimeModules` to discover the two on
     the import path (regenerating their `.sym` first), and to put them at
     the *front* of the module list (a program that imports them itself
     has them moved there). The runtime directory therefore has to be on
     `POC_IMPORT_PATH`/`-import-path`; there is no built-in default - a
     missing runtime is reported as an error naming the module, not
     silently mislinked. If the program lacks the module (a hand-built
     `ModuleList`), `Allocate` is `declare`d instead.
   - *Records with no descriptor*: `EnsureTypeTag` gives a record written
     inline under a `POINTER TO`, or declared inside a procedure, the
     unwritable name `-anon<n>` (`$anon<n>` until Phase 11 A25) the first
     time `NEW`/`IS`/a guard/`WITH` names it (its base record first), and
     `EmitPointerSupport` emits the
     descriptor at the end of the program. Module-level records are as in
     step 1. Only a record of *another* module that is itself unnamed on
     this side (an inline record under an imported pointer) still cannot
     be named - `; unsupported`.
   - *`IS`, guards, `WITH`*: `EmitTagTest` reads the tag word before the
     data, then `BaseTypes[Level(T)]` - but only when the record is at
     least that deep (`extLevel >= Level(T)`; otherwise it reads
     `BaseTypes[0]`, which can never equal a non-root `T`'s tag), so the
     one-line report translation is branch-free after the NIL test.
     **NIL semantics** (the report is silent; probed against voc, which
     traps "NIL access" on all three, and matched exactly): `NIL IS T`,
     the guard `NIL(T)` and a NIL `WITH` variable all take the ordinary
     NIL-dereference trap (`nilderef`, exit 4) - `EmitTypeTest`/
     `EmitTypeGuard`/the WITH tests call `EmitNilCheck` first, so
     `EmitTagTest` never sees NIL. (An earlier draft made `NIL IS T`
     FALSE, the guard pass and the WITH variable match nothing; that
     accepted programs voc rejects at run time, so it was dropped.) A
     guard on a non-NIL pointer of the wrong type fails with `typeguard`
     (exit 5). Both the pointer and the bare-record spelling of `T` are
     accepted, as in the checker. `WITH` is an IF-chain; the branch body
     is generated with a `Narrowing` pushed, the string-literal pre-pass
     now walks `WITH` bodies (it did not - a literal inside a branch would
     have named an undefined global). Guards on a `VAR` record parameter
     (which needed the hidden tag argument) came with step 6.
   - *`&`/`OR` are short-circuited at last, always* (the Phase 8 step 5
     simplification was flagged "revisit once a call or a trap makes it
     observable" - a NIL check makes it observable): `GenerateShortCircuit`
     branches around the right operand and joins with a `phi` naming the
     block the right operand *finished* in (`Codegen.currentBlock`, kept by
     `EmitLabel`, whose signature therefore gained `cg`). A first version
     kept the eager `and`/`or` for a side-effect-free right operand
     (`IsSideEffectFree`); it was removed - two code paths for one
     operator bought only smaller IR for trivial operands, at the price of
     a purity predicate that had to track every future trapping operation
     (each new one, like an index or a NIL check, would have had to be
     added to it). Regenerated goldens: `llvm-reals-ir`,
     `llvm-straight-line-arithmetic` and `llvm-system-ir` (each diff only
     `and`/`or` becoming branch + `phi`), plus `llvm-pointers-ir` and
     `llvm-type-guards` (that, and `IS`/guards now NIL-checking instead
     of carrying a NIL branch).
   - *Other changes*: a local variable holding a pointer (or a record/
     array containing one) is `zeroinitializer`ed on entry - Oberon2.pdf
     6.4 says every pointer starts NIL, and it makes a never-assigned
     local a NIL trap rather than a wild access
     (`llvm-type-descriptors-hidden-members-ir`'s golden gained the store);
     `r1 := r2` where `r2` is an extension of `r1`'s type copies the base
     part (`extractvalue ..., 0` per level, `NarrowRecordValue`) - `clang`
     rejected the first attempt at the golden IR, which is what found it.
   - *Fixtures*: `llvm-pointers` (a `NEW`-built chain, zero-filled blocks,
     `^` record copy, pointers to fixed arrays, extension fields, `&`/`OR`
     over NIL), `llvm-pointer-shapes` (inline-anonymous and procedure-local
     records, `VAR` pointer and `p^` parameters, arrays of pointers, a
     record's embedded pointer array, function results), `llvm-pointer-
     fields` (string compare/`COPY`/`INC`/`INCL`/`LEN`/`CASE`/`FOR` through
     a pointer), `llvm-type-guards` (a three-level hierarchy plus a sibling:
     `IS`, guards as expressions and designators, `WITH` incl. `ELSE`; NIL
     operands live in `llvm-pointer-traps`, so the whole fixture now runs
     under real voc too and was cross-checked against it),
     `llvm-short-circuit` (call counters, index and NIL operands, the
     classic `WHILE (p # NIL) & ...` loops), `llvm-pointer-traps` (one
     program per trap: NIL through `.`, `^`, a chain, `[`, an unassigned
     local; `NIL IS T`, a guard and a `WITH` on NIL, each cross-checked
     against voc's own "NIL access" trap; a failed guard; an unmatched
     `WITH`; heap exhaustion, which is *not* a trap - `NEW` leaves NIL,
     as voc's does, and the program then prints and exits 0 until it
     dereferences it, while `heapfull` does so and traps with exit 4),
     `llvm-pointers-multi-module` (a pointer type, constructor and hidden
     field from an imported module; `NEW` of the imported record and of a
     local extension of it, laid out from the `.sym`; `IS`/guards/`WITH`
     across the boundary; objects from both modules linked into one chain
     under a small heap cap), `llvm-gc-new` (the collector driven by compiler-emitted descriptors
     and root tables: a 1 MB cap, several MB of garbage, a chain, an array
     of pointers, an embedded pointer array and a tree held only by a
     local survive; the same negative experiments as step 4 - no stack
     scan, no module tables - fail it), `llvm-pointers-ir` (golden `.ll` of
     the fixture's own part at both word sizes with register/label numbers
     normalized, so runtime changes cannot renumber it; `clang -c`
     validated), and all the runtime ones added to `llvm-i686-runtime`.
     `llvm-gc-new`'s reclamation checks are deliberately relative: the
     stack scan is conservative, and on i686 a stale word in a live frame
     kept a suffix of the chain alive (33 KB after dropping it, against 1
     KB on x86-64) - a real property of the design, not a bug.
   - *Known gaps, none new to this step*: `NEW(p, n)` and a pointer to an
     open array (step 7, done); type-bound calls (step 6, done); a procedure *value*
     (`proc := P`; comparing a procedure variable with `NIL` works, but
     naming a procedure as a value was `; unsupported` and, because
     `Unsupported` gives a mistyped placeholder, invalid IR; no step owned
     this, so it was listed under step 8, where it is done); a record value's LLVM type text is cut at 63
     characters (`ValueText`) - only a huge record loaded whole is
     affected, and it predates this step.

6. **Type-bound procedures and dispatch.** Each record type's `ProcTab`
   (step 1) is populated at module-init time with the addresses of its
   own bound procedures (inherited entries filled in from the base
   type's own slots where not overridden, per Fig. D5.1's layout);
   `t.P(...)` lowers to `t^.tag^.ProcTab[IndexP](...)`, and `P^(...)`
   (explicit base-method call, §10.3) indexes the *declared* receiver
   type's own `ProcTab` slot directly rather than dispatching. Receiver
   binding (`PROCEDURE (t: Tree) Insert...`) reuses ordinary-parameter
   codegen (Phase 8 step 10) with the receiver as an implicit first
   parameter.
   **Testing**: the report's own `Tree`/`CenterTree`/`Node` dispatch
   example (already this project's Phase 6 exit-gate fixture family) as
   a real compile+link+run+diff fixture — the natural capstone for
   dispatch, since it's the report's own canonical worked example and
   this project already has the front-end-only version of it checked.

   **Implemented 2026-09-19.** Points where `Oberon2.pdf` is silent or
   poc had to choose (all probed against real voc the same day):
   - *Bodies and symbols*: `GenerateMethodDecl` defines each type-bound
     procedure as `@<Module>.<Record>.<Procedure>` (a pointer-receiver
     `(t: Tree)` binds to `Tree`'s record; a record written inline under
     `Tree = POINTER TO RECORD` is `Tree.base`), receiver first, sharing
     `GenerateProcedureBody` with ordinary procedures - so step 1's
     `declare`s are gone (`EmitMethodDeclares` removed) and three
     descriptor goldens (`llvm-type-descriptors-*-ir`) gained the real
     bodies. The receiver is a bare `ptr` either way: a VAR record
     receiver is the record's address, a pointer receiver the pointer,
     which is the same address, so one calling sequence serves both.
   - *Hidden tag argument* (`NeedsHiddenTag`, decided here - the step 5
     note left it open): every VAR parameter of **record** type, a VAR
     receiver included, is passed as `ptr %x, ptr %x.tag` - the actual's
     type descriptor - because the actual may be an extension of the
     declared type and the callee must dispatch on, and test, what it
     really is (voc does the same). It sits right after its parameter; a
     `["C"]` external procedure gets the bare address (a fixture writes a
     record through `write(2)` to prove a tag would shift its
     arguments). VAR pointers, VAR arrays and value parameters carry none.
     The convention is part of the ABI of any procedure with such a
     parameter, so **procedure values** (step 8, done) pass the tag too.
     `DynamicType` says where an actual's tag comes from: a record
     variable, field or element is exactly its declared type (its own
     descriptor), `p^` is whatever the heap block says, a VAR parameter
     passes its own hidden tag on. Value record parameters take an
     extension too, copying only the base part (`NarrowRecordValue` now
     also applies to call arguments; real voc's generated C rejects this
     one).
   - *Dispatch* (`GenerateMethodCall`): `v.P(...)` calls through
     `tag - (slot+1)*W` when the receiver's dynamic type is not known
     exactly, straight to the procedure that slot holds for the static
     type when it is (`SlotOfMethod`, matched by `Method` identity, not
     name - hidden and new same-named procedures hold different slots).
     `v.P^(...)` is a direct call of the procedure `Types.FindMethod`
     finds on the base of `v`'s static type. A NIL pointer receiver is the
     ordinary NIL trap (exit 4), before the procedure starts; voc traps
     the same ("NIL access"). A pointer-receiver procedure needs a real
     heap block behind it (a callee may read the tag word), so calling it
     on a record variable is `; unsupported` rather than handed a
     "pointer" to a variable.
   - *Guards on VAR record parameters* (the front-end half was missing
     too; step 5 had assumed it existed): `IS`, `v(T)` and `WITH` accept
     a VAR parameter of record type, judged by
     `SemanticActions.lastDesignatorIsVarParam` since a designator's type
     alone cannot say. Matched to voc's own rules (its error 87): only
     the parameter's own name qualifies - a plain record variable, a value
     parameter, and `x(T)(U)` / `x(T) IS U` are rejected - while a guard
     and a test on the WITH-narrowed parameter inside its branch are
     accepted, and `v(T)` may be passed on as a VAR argument. The
     codegen tests the hidden tag (`EmitTagTestOnTag`,
     `EmitTypeGuardOnTag`).
   - *Discovered along the way, fixed*: an extension record passed to a
     value record parameter emitted an ill-typed call; a qualified
     variable (`M.v`) as a VAR argument was `; unsupported` for no reason.
   - *Fixtures*: `llvm-type-bound` (pointer receivers three levels deep
     plus a sibling, `^` chains, self-dispatch, receivers that are fields,
     array elements, guards, `WITH` variables and locals, VAR receivers on
     variables, fields, elements and heap blocks, a base pointer holding
     an extension, a bound procedure's own VAR record parameter, dispatch
     inside a short-circuited operand), `llvm-var-record-params` (the hidden tag: relayed,
     from `p^`/fields/elements/locals, two per call, `IS`/`WITH`/guards,
     a procedure-local record type, the external-`write` regression),
     `llvm-type-bound-multi-module` (overriding an imported procedure, a
     hidden imported procedure holding a slot its importer cannot
     override, library code dispatching to importer overrides, VAR
     receivers and VAR arguments of imported types, imported variables as
     receivers), `llvm-trees-dispatch` (the report's own `Tree`/
     `CenterTree` example with a recursive bound `Write` dispatching
     through pointer fields; its `Trees` module proper needed step 7's open
     arrays - `llvm-trees-strings` has it), `llvm-type-bound-ir` (golden `.ll` at both word sizes, `clang -c`
     validated), five `llvm-pointer-traps` programs (NIL through a
     pointer receiver, a VAR receiver and a `p^` VAR argument; a failed
     guard and an unmatched `WITH` on a VAR parameter) and three `semantic-*`
     fixtures. All the runtime ones also run as real i686 executables.
     Every behavior above was cross-checked against real voc except two
     things voc cannot do: a bound call through a record written inline
     under a `POINTER TO` (voc gives it no descriptor and traps "NIL
     access"; it is the fixture's last check for that reason) and
     extension-to-value-parameter (its C does not compile).
   - *Found, not fixed (pre-existing, unrelated)*: constant arithmetic on
     literals is not folded - `2 * 100 + 2 * 10` is typed `SHORTINT` and
     wraps at 8 bits at run time, where voc folds it to 220.

7. **Open-array dope vectors.** Open-array formal parameters (`VAR`
   and value) pass a hidden length parameter per dimension alongside
   the data pointer, matching voc's own convention already cited in
   Phase 8 step 4's retrospective; `NEW(v, x0, ..., xn-1)` (§10.3's
   multi-dimensional open-array allocation form, Appendix A's own
   table) allocates and populates the dope vector accordingly; `LEN`'s
   existing two-argument form (already lowered in Phase 8 step 11 for
   fixed arrays) extends to read a real dope-vector length at those
   dimensions rather than a compile-time-known one. Directly closes the
   one gap Phase 8 step 11's own retrospective explicitly called out and
   routed around ("forwarding an `ARRAY OF CHAR` value parameter into
   another call... stays unexercised... open arrays are a known,
   narrow, not-yet-built convention").
   **Testing**: an open-array `VAR`-parameter fixture forwarding a
   value between two procedures (Phase 8 step 11's own deferred case,
   finally exercised for real), and a multi-dimensional `NEW(v, x0, x1)`
   fixture.

   **Implemented 2026-09-19.** The convention (`LLVMCodeGenerator.Mod`'s
   section on open arrays has the reference text; every point probed
   against real voc, whose runtime source was read for the heap layout):
   - *Parameters.* An open-array parameter, `VAR` or value, is
     `ptr %a` then one `%a.len<d>` per open dimension (`OpenDimCount`),
     each a word-sized integer - the target's word size, like every other
     size-dependent quantity this phase (voc's are `ADDRESS`); an external
     `["C"]` procedure keeps the bare `ptr` (Phase 8 step 6's decision,
     unchanged - `ParamLLVMType`). A *value* parameter is copied on entry
     into an `alloca` of `product(lengths) * sizeof(element)` bytes with
     `llvm.memmove` (voc copies too - probed: assigning to the parameter
     leaves the caller's array alone). `MemoryLayout.DescriptorSize`'s
     "4-byte length words" became word-sized to match.
   - *Designators.* `DesignatorAddressTo`'s `DynamicType` gained a
     `DopeVector`: an open-array parameter's binding carries its lengths,
     `[` on one checks `idx <u len` (`EmitOpenIndexCheck`, at the wider of
     the index and the word, so a `HUGEINT` index on 32 bits is not
     truncated) and steps by the element (`EmitElementGEP`) - or, when the
     element is itself an open array, by the product of the inner lengths
     in bytes, leaving the address of the inner array and the remaining
     lengths (so `a[i, j]`, `a[i][j]` and `a[i]` passed on all work).
   - *Arguments.* `GenerateOpenArrayArg` takes any array designator (fixed
     dimensions contribute their constant length, open ones the dope
     vector's) and, for a value `ARRAY OF CHAR`, a string literal or named
     `STRING` constant (length = characters + 0X, as voc's `LEN("abc")`).
     `GenerateStringArgValue` is gone; `GenerateCharSequence` reports a
     word-sized length text instead of a `LONGINT`, so comparison and
     `COPY` take open `ARRAY OF CHAR`s (`EmitLengthAsI32` narrows, clamping,
     for the `i32` helpers).
   - *Pointers.* `POINTER TO ARRAY OF ...` points at a block laid out as in
     voc: the lengths (one word per open dimension), then the elements at
     `OpenDataOffset` (the lengths rounded up to the element's alignment).
     `DereferencePointer` loads the lengths into the designator's dope
     vector and continues from the first element. `NEW(p, n0, ..., nk-1)`
     (`GenerateNewOpenArray`) does the size arithmetic in 64 bits with
     `llvm.umul/uadd.with.overflow` (a 32-bit target must also fit a word),
     traps - new exit 7, voc's own message for its `Halt(-20)` - when any
     length is not positive or the size overflows, allocates through
     `GarbageCollectedHeap.Allocate`, stores the lengths if a block came
     back (NIL, not a trap, if not - as for a record) and then the pointer.
   - *Collector.* The block's tag is the array descriptor of the innermost
     element type (`ArrayTagOperand`, `InnermostOpenArray`), as for a fixed
     array of pointers. The collector walks a block as a run of elements
     from its start, so when the elements hold pointers `OpenDataOffset`
     rounds the header up to a whole number of elements: the lengths are
     then read as a few elements' pointer fields, a spurious candidate at
     worst (they are at most 2^25, below any heap address).
     `llvm-open-array-new` fails if the descriptor is dropped (checked).
   - *Front end.* One gap surfaced: `CheckArguments` demanded the *same*
     type of a `VAR` open-array parameter's argument (`Types.SameType`,
     which two independently written open-array types never satisfy),
     so an open array could not be forwarded, and a fixed one could not be
     passed to a `VAR ARRAY OF` at all - now `IsOpenArrayFormal`
     (`Types.ArrayCompatible`). voc accepts and rejects exactly the same
     sets (both semantic fixtures were run through it).
   - *Also fixed*: `LEN` was typed `INTEGER` by the code generator but
     `LONGINT` by the checker, so a length above 32767 wrapped -
     `GenerateLen` now returns `LONGINT` (`llvm-predeclared-ir`'s golden
     changed by exactly that).
   - *Testing.* `llvm-open-array-params` (`VAR` and value parameters,
     forwarding, a value parameter's private copy, 1- and 2-dimensional
     arrays given fixed arrays and rows, strings, `COPY`, comparison,
     records as elements, recursion, a bound procedure, an open array
     handed to an external C procedure), `llvm-open-array-new`
     (`NEW(v, n)`, `NEW(m, n, k)`, a 3-dimensional one, an open outer
     dimension over a fixed element, characters, arrays reached through
     record fields, an index wider than a word, and the collector run over
     50 pointer-holding arrays), `llvm-trees-strings` (Chapter 11's `Trees`
     as a library - `Insert(name: ARRAY OF CHAR)`, `NEW(p.name,
     LEN(name)+1)`, `COPY`, `name = p.name^` - across a module boundary),
     `llvm-open-array-traps` (index past either end, through a parameter, a
     pointer and the inner dimension; NIL element and NIL `LEN`; zero,
     negative, inner-zero and overflowing lengths; a too-big request
     answering NIL), `llvm-open-array-ir` (golden `.ll` at both word
     sizes, `clang -c` validated) and two `semantic-*` fixtures; the
     runtime ones also run as real i686 executables (the trap programs by
     hand). Cross-checked against real voc: every check of the first three
     agrees except the one below.
   - *Found, not fixed*: voc passes `a[r]` of a multi-dimensional open
     array with no row stride (AGENTS.md, "Known voc bugs"), so one check
     of `llvm-open-array-params` differs under voc - poc is right. voc
     rejects a constant length <= 0 in `NEW` at compile time; poc traps at
     run time. An open array with more than 8 dimensions, and elision of a
     value parameter's copy when it is never written, are not done.

8. **Complete `PredeclaredProcedures.Mod` lowering.** Sweep whatever
   remains `Unsupported` once steps 1–7 land — expected to be a short
   list by this point, since `NEW` (step 5), `LEN`'s open-array form
   (step 7), and every REAL/SET-related gap (steps 2–3) are the only
   §10.3 procedures Phase 8 step 11's own retrospective named as out of
   scope. Pick up `ASSERT` here only if `PLAN.md`'s own open design
   question above has been resolved by then; otherwise leave it exactly
   as undecided as it is now.
   Also here: procedure *values* (`proc := P`, passing a procedure as an
   argument), found unlowered by step 5's testing - `GenerateDesignatorValue`
   reports a procedure name `; unsupported`, and `Unsupported`'s placeholder
   for an untyped result is `0`, which is invalid IR where a `ptr` is
   stored.
   **Testing**: whatever fixture gaps steps 1–7 didn't already close on
   their own.

   **Implemented** (2026-09-19; all probed against real voc). What
   changed, and what a program can observe:
   - *Procedure values.* A procedure's name used as a value is the address
     of its function (`ptr @Module.Proc`, `GenerateDesignatorValue`); it can
     be assigned to a variable, record field or array element, passed as an
     argument (a `VAR` parameter of procedure type too), returned from a
     function, compared with `=`/`#` against another procedure-typed *value*
     or NIL, and called through any of them (`GenerateProcedureValueCall`:
     the designator is loaded, NIL-checked - the usual exit-4 trap, voc's
     "NIL access" - and called indirectly). The arguments are laid out from
     the procedure *type's* parameter list, hidden arguments included (a
     `VAR` record's tag, an open array's lengths), which is exactly what
     every procedure that matches the type expects - so `Inspect(VAR s:
     Shape)` called through a value still sees `s`'s real type. A local
     variable of procedure type (or a record/array holding one) is zeroed on
     entry like a local pointer (`ContainsProcedureValue`): poc guarantees
     that calling one never assigned traps, where voc leaves it as stack
     garbage. The collector is unaffected - a procedure holds no heap
     address, `CountPointerSlots` still skips it, and a record mixing
     procedure and pointer fields is traced whole (checked).
   - *Front end.* `CheckProcedureValue` (Oberon2.pdf 6.5: "P must not be a
     predeclared or type-bound procedure nor may it be local to another
     procedure") rejects a type-bound procedure (`CheckDesignator` now
     reports whether a designator ended in one, `lastDesignatorIsBoundProcedure`)
     and a nested one used as a value; poc also rejects an *external* one
     (it is called with the C convention, a procedure value with the Oberon
     one - there is no such thing in voc). A predeclared one already failed
     as not having a procedure type. And a procedure's *name* is no operand
     of `=`/`#` (`NamesProcedure`): Appendix A lets it stand for the
     procedure only in an assignment or as an argument, and voc agrees
     ("this expression cannot be a type or a procedure") - poc used to
     accept `f = P`. voc rejects the same forms with the same reasons
     (`semantic-reject-procedure-value`).
   - *ASH.* `ASH(x, n)` shifts left for `n >= 0` and right, sign-filling,
     for `n < 0`, in the wider of `LONGINT` and `x`'s own type -
     `CheckAsh` used to say `LONGINT` always, losing a `HUGEINT` operand's
     top bits; voc's own rule is "LONGINT, or INT64 if larger". A count of
     the type's width or more is not left to LLVM (poison): everything is
     shifted out, leaving 0 (or the sign, for a right shift) - identical to
     voc for counts up to 63, past which its C shift is undefined (those
     checks are `poc only` in the fixture). Branch-free, via `select`.
     voc computes in 64 bits and truncates on assignment, so a `LONGINT`
     result that overflowed compares differently *unnamed* (`ASH(1, 31) =
     MIN(LONGINT)` is false under voc) - the fixture stores it first.
   - *MAX/MIN.* `MaxMinBound` (now exported) already gave the constant
     folder every bound but REAL/LONGREAL; `GenerateMaxMin` emits them for
     the run-time expression form (`i := MAX(SHORTINT)`), and the two real
     types as their IEEE largest finite values and negations. voc's
     `MAX(LONGREAL)` is a deliberate underestimate (`OPM.Mod`:
     `1.7976931348623157D307 * 9.999999`, "should be ...D308"); poc gives
     the true one. `CONST` folding of `MAX(REAL)`/`MAX(LONGREAL)` is still
     not done (the entry under "Open design questions" stands).
   - *ASSERT* left exactly as undecided as before.
   - *Found and fixed on the way*: `AppendLongInt` emitted a bare `-` for
     the most negative `LONGINT` (`MIN(HUGEINT)`, or a `HUGEINT` constant of
     that value) since it negated the value to build the digits.
     `EmitConstantValue` split out of `GenerateConstValue` so a folded bound
     is emitted like a `CONST`.
   - *Testing.* `llvm-procedure-values` (41 checks: every place a value can
     live and be called through, argument passing two levels deep, results
     of each kind including a pointer and a procedure, hidden tag and
     lengths, locals, recursion through a variable, the collector),
     `llvm-procedure-values-import` (`Calc.Add` as a value, an exported
     procedure-typed variable and record field, across a module boundary),
     `llvm-procedure-value-traps` (a NIL procedure called as a global, a
     never-assigned local, a heap record's field, an array element, a
     proper procedure, a `NIL` argument, and through a NIL pointer - all
     exit 4, and all "NIL access" under voc), `llvm-procedure-values-ir`
     (golden `.ll` at both word sizes, `clang -c` validated),
     `llvm-ash-max-min` (62 checks, all three integer widths, `HUGEINT`
     operands and counts, every `MAX`/`MIN`) and
     `semantic-reject-procedure-value`; the three runtime fixtures also run
     as i686 executables (`llvm-i686-runtime`). Cross-checked against real
     voc (`llvm-procedure-values` and `llvm-ash-max-min` - minus the `poc
     only` part - print `OK` under it; the trap programs give "NIL access"
     each).
   - *The `Unsupported` placeholder* is no longer reachable with a pointer
     or procedure result: the sites that produced one (a procedure name as
     a value, a call through a value) are lowered, and the remaining ones
     take a type the checker has already fixed or are unreachable for a
     program it accepts.
   - *Not done*: `CONST` `ASH(...)`/`MAX(REAL)`, and folding of *integer
     literal arithmetic* (`2 * 100 + 2 * 10` wraps at `SHORTINT` width
     where voc folds it) - both pre-existing and unrelated to this step;
     they are step 10's (Catching Up).

9. **32-/64-bit parity sweep.** Run the *entire* conformance suite —
   not a promoted subset — compile+link+run+diff on both a 32-bit and
   a 64-bit LLVM target, on Linux and at least one BSD (reusing Phase 8
   step 13's real-hardware access, `erekose`/OpenBSD-i386 and
   `terhali`/NetBSD-x86_64, rather than assuming portability from a
   single platform). This is the phase's own explicit exit gate, listed
   here as its own step rather than folded into the individual feature
   steps above precisely because it must run *after* all of them, over
   everything at once, the same way Phase 8 step 13 only found the
   datalayout bug once real fixtures actually ran on real 32-bit
   hardware.
   **Testing**: `make test` clean on every combination; any fixture
   that only passes on one word size or platform is a real bug, not an
   acceptable gap, at this point in the project.

10. **Catching Up.** Three constant-folding gaps found while
    implementing steps 5-8, each pre-existing and none in those steps' own
    scope; all three make poc reject, or mis-type, something real voc
    accepts and folds. Listed after step 9 because none blocks the parity
    sweep (every fixture so far avoids them), but the sweep is re-run over
    the whole suite once this lands - see **Testing** below. Every
    behavior below is to be probed against real voc first (`PLAN.md`'s
    standing convention), not assumed from the notes that found the gaps.
    - *Folding of integer literal arithmetic.* `2 * 100 + 2 * 10` is typed
      `SHORTINT` and wraps at 8 bits at run time; voc folds it to 220.
      `ConstantEvaluator.IntegerLiteralType` gives a bare numeral its
      minimal type (Oberon2.pdf §5), but a *computed* constant keeps the
      type of its operands: `Types.WiderOf` of two `SHORTINT`s, whatever the
      result's value needs. Two halves: (a) an ordinary *expression* whose
      operands are all constants (`SemanticActions.CheckExpr` and
      `LLVMCodeGenerator`, which never fold - the wrapping above happens
      there) is folded to a constant of the minimal type its value fits,
      as voc's `OPB` does; (b) `CONST` folding likewise re-derives the
      minimal type from the computed value instead of keeping the
      operands' (`000-todo.org`'s `MAX(SHORTINT) + 1` entry, which real voc
      rejects and poc types `SHORTINT`). Decide from voc's own behavior
      what happens when the value fits no type (`HUGEINT` overflow -
      `ConstantEvaluator` already reports "integer literal too large" for a
      numeral, so a computed overflow should be the same kind of error, not
      a silent wrap), and whether `DIV`/`MOD`, unary minus and the six
      relations fold too (they should: a constant expression is a constant
      expression). Both size models (`-O2`/`-OC`) change which type a value
      lands in, so the folder must use the current model, as
      `IntegerLiteralType` already does.
    - *`CONST` `ASH(x, n)`.* The first *value-argument* predeclared
      function `ConstantEvaluator` has to fold: `MAX`/`MIN`/`SIZE` take a
      bare type name and needed no general machinery (see "Open design
      questions"), but `ASH` must evaluate its two arguments as constant
      expressions and apply the shift. Same result type as
      `PredeclaredProcedures.CheckAsh` (the wider of `LONGINT` and `x`'s
      type). voc reports a constant `ASH` whose count is beyond the
      machine's `maxExp`, or whose left shift overflows 64 bits, as
      error 208 (numerical overflow) - probe the exact boundaries and match
      them rather than the run-time semantics `GenerateAsh` gives (which
      define a count past the width as 0/sign). Whether the same machinery
      is then extended to the other value-argument functions (`ORD`/`ABS`/
      `CHR`/`CAP`/`ODD`/`LONG`/`SHORT`/`ENTIER`, all deferred alongside)
      is optional here: `ASH` is what this step commits to, built so the
      others are one small case each.
    - *`CONST` `MAX(REAL)`/`MIN(REAL)`/`MAX(LONGREAL)`/`MIN(LONGREAL)`.*
      `ConstantEvaluator.MaxMinBound` still returns FALSE for these; the
      run-time expression form is done (`GenerateMaxMin`: IEEE 754's largest
      finite values, 3.4028234663852886D38 and 1.7976931348623157D308 - voc's
      own `MAX(LONGREAL)` is deliberately a little low, so poc's value
      differs from voc's by design, documented in AGENTS.md). The constant
      form has to build those two `LONGREAL` values inside poc's own
      source *without* writing them as literals - voc rejects a `REAL`
      literal with exponent 38 and a `LONGREAL` one with exponent 308
      (AGENTS.md, "Known voc bugs"), the same workaround
      `LLVMCodeGenerator.DoubleBitsText`'s `twoTo52` loop already uses (or
      assemble them arithmetically from their bit patterns). Then the
      folded value must round-trip through `ModuleInterface.Mod`'s
      `.sym` writer (a `CONST` exported from a module: tier 2's
      `FormatReal`, since it is not a bare literal) and be emitted by
      `RealConstant` exactly, including at `REAL`'s single precision.
    **Testing**: for each gap a positive fixture (`poc -check`, plus a
    compile+link+run one where the value is observable at run time -
    `2 * 100 + 2 * 10` compared with 220 is the direct regression), a
    negative one for what voc rejects (a folded overflow, `MAX(SHORTINT) +
    1` in a `CONST`, an `ASH` past `maxExp`), a `.sym` round-trip for a
    `CONST` of each new kind, all under both `-O2` and `-OC` where the
    size model matters, and cross-checked against real voc (the `MAX`
    constants excepted, by design, for `LONGREAL`). This step's fixtures
    are ordinary `make test` fixtures, so **the step 9 sweep is re-run in
    full** - both word sizes, Linux and at least one BSD - after it lands,
    and Phase 9 is not done until it is clean.

    **Implemented** (2026-09-19; every behavior below probed against real
    voc, both size models). What changed, and what a program can observe:
    - *Folding integer arithmetic.* A constant integer operation is carried
      out in 64 bits (`ConstantEvaluator`: `SumOverflows`/
      `DifferenceOverflows`/`ProductOverflows`, `IntegerResult`), whatever
      the operands' types, and its result takes the *minimal type its value
      fits* (`MinimalIntegerType`, which `IntegerLiteralType` now shares) -
      `2 * 100 + 2 * 10` is the INTEGER 220, `MAX(SHORTINT) + 1` an INTEGER,
      and `-128` a SHORTINT though `128` is an INTEGER (unary minus re-types
      too; unary `+` folds now). It is an error only when the value does not
      fit HUGEINT, where voc's `OPB.ConstOp` reports errors 203-207: "constant
      sum/difference/product/negation too large for HUGEINT". A constant
      `DIV`/`MOD` folds floored; a zero divisor is "division by zero", as
      before. Integer constants compare as integers now (`EvaluateEquality`/
      `EvaluateOrder` went through LONGREAL, so a `CONST` `MAX(HUGEINT) =
      MAX(HUGEINT) - 1` was TRUE). This is one mechanism for `CONST`
      declarations and for ordinary expressions: `ConstantEvaluator.
      IsConstantExpr` (silent - `Evaluate` reports) says whether every leaf
      is a literal, a named constant, `MAX`/`MIN`/`SIZE` of a type name or a
      constant `ASH`; `SemanticActions.FoldIntegerConstant` (`CheckExpr`,
      for a unary or binary expression or an `ASH` call) then gives the
      expression the folded value's type, and `LLVMCodeGenerator.
      GenerateFoldedInteger` emits the folded value as one immediate of that
      type, so the checker and the generator cannot disagree. Only an
      *integer-typed* result is folded: a constant real, BOOLEAN or SET
      expression is left to the rank rules and to LLVM (it can neither wrap
      nor be mistyped), and so is a relation of two constants - an error
      inside one (a division by zero) is still found, in the operand.
    - *Two host bugs worked around, one voc bug not reproduced.* poc is built
      with voc, whose `DIV`/`MOD` are wrong for a negative dividend within
      the divisor of `MIN(LONGINT)` (`MIN(LONGINT) DIV 2` comes out positive),
      so `FloorQuotient`/`FloorRemainder` never divide such a value, and
      `ProductOverflows` uses no negative dividend either. As a result poc
      accepts a product of exactly -2^63 (`(-2^62) * 2`), which voc rejects
      (its own check divides `MIN(INT64)`, apparently through the same bug). `MIN(HUGEINT) DIV (-1)` is "constant quotient
      too large" - voc's compiler dies of SIGFPE folding it.
    - *`CONST` `ASH(x, n)`* (`EvaluateAsh`): both arguments constant
      integer expressions; a count outside -62..62 (voc's `maxExp`) or a left
      shift with `ABS(x) > MAX(HUGEINT) DIV 2^n` is an error ("constant ASH
      count out of range" / "result too large") - the same boundaries as
      voc's error 208, probed at 62/63, -62/-63, `ASH(3, 62)`, `ASH(MAX(
      HUGEINT), 1)` - and a right shift floors. The type is the wider of
      LONGINT and `x`'s, *and no narrower than the value needs*: voc types
      `ASH(1, 40)` a LONGINT under `-O2` and silently keeps 32 bits (0),
      where poc makes it a HUGEINT, so assigning it to a LONGINT is a
      compile-time error (`semantic-reject-const-ash-too-wide`; under `-OC`
      it is fine, `oc-flag-const-ash-fits-longint`). Like voc, and unlike
      `+`, the result is not re-typed *downward*: `ASH(1, 3)` stays a
      LONGINT. The other value-argument functions were folded afterwards
      (Phase 11 step 2, 2026-09-20: `EvaluateValueFunction`).
    - *`CONST` `MAX`/`MIN` of `REAL` and `LONGREAL`* (`MaxMinBound`): IEEE
      754's largest finite value and its negation, built from powers of two
      (`MaxReal` = 2^128 - 2^104, `MaxLongReal` = 2 * (2^1023 - 2^970), both
      exact) since voc rejects the literals. `GenerateMaxMin` now takes every
      type from `MaxMinBound` and `RealConstant` writes the value's bit
      pattern (`0x47EFFFFFE0000000`, `0x7FEFFFFFFFFFFFFF`), so the constant
      and the run-time form cannot differ. The value written to a `.sym`:
      `ConstantEvaluator.ParseReal` cannot read `1.7976931348623157D308`
      back exactly (308 multiplications by ten drift), so tier 2 of the real
      exporter fails for it; `ModuleInterface.ExtremeRealSpelling` prints a
      value that is exactly the largest finite one of its own type, or its
      negation, as `MAX(LONGREAL)`, `MIN(REAL)` and so on, which the reader
      folds back exactly (`module-interface-const-fold`, `-O2` and `-OC`,
      with the interface read back as source and required to reproduce
      itself). *Not fixed*: any other computed real of extreme magnitude
      (`MAX(LONGREAL) / 2`, `1.0D300 * 1.5`) still cannot be exported, for
      the same reason - it was so before this step; Phase 11 step 2 has it.
      A folded integer prints as its value, so its type after a `.sym`
      round trip is the minimal one (`ASH(1, 3)` is a SHORTINT to an
      importer, a LONGINT at home); every other constant already worked so.
    - *Fixtures* (174 pass): `semantic-const-fold-integer` (accepted, voc-
      clean), `semantic-reject-const-fold-narrow` (nine assignments, each
      rejected by voc too), `semantic-reject-const-fold-overflow` (every
      error class, in `CONST` and in statements), `semantic-reject-const-
      quotient-overflow`, `semantic-reject-const-ash-too-wide`, `oc-flag-
      const-ash-fits-longint`, `module-interface-const-fold`, `llvm-const-
      fold` (52 checks, 50 of them cross-checked under voc - the rest are
      poc-only: voc's `MAX(REAL)` reaches the C compiler at 8 digits and
      its `MAX(LONGREAL)` is low by design), `llvm-const-fold-import` (the
      constants through a `.sym`), `llvm-const-fold-ir` (`-O2` and `-OC`
      goldens), and both new run fixtures in `llvm-i686-runtime`. Three
      existing IR goldens changed only by folding (`llvm-predeclared-ir`,
      `llvm-system-ir`, `llvm-straight-line-arithmetic`); the last one's
      `(-7) DIV 2` is now `minusSeven DIV 2` on a variable, so its floored
      DIV/MOD code is still generated and checked.
    - *The step 9 sweep after this step*: the whole suite passes on Linux at
      both word sizes (64-bit, and the 32-bit `i686` runs in `llvm-i686-
      runtime`). **Not run: any BSD** - the BSD hosts were unreachable this
      session - so Phase 9 is not yet done by its own criterion; Phase 11
      step 8 carries the outstanding BSD runs.

**Testing summary**: golden-`.ll`-diff fixtures for the purely static
pieces (step 1, and step 4a's `.sym` writer/checker fixtures plus its one
cross-module descriptor golden), promoted to compile+link+run+diff everywhere else,
matching Phase 8's own testing posture — culminating in step 9's
whole-suite/whole-platform-matrix gate, re-run once step 10 (Catching Up)
has added its own fixtures. Self-hosting is Phase 10's own
exit gate, not this phase's.
