# Design decisions

Questions `PLAN.md`'s "Open design questions" once held, now decided, moved
here unchanged on 2026-09-25. `PLAN.md` keeps the questions that are still
open and lists these by name, so a reference to `PLAN.md`'s "Open design
questions" - <name> means the entry of that name here.

- **No `ASSERT`**: `Oberon2.pdf`'s §10.3 predeclared-procedure table has
  no `ASSERT` entry (confirmed against the report; see
  `PredeclaredProcedures.Mod`'s header comment), so poc doesn't have one
  either. Every dialect surveyed beyond the strict report adds one, and
  the dominant convention (Component Pascal, and Oberon+ copying it
  verbatim) is a two-argument overload: `ASSERT(x)` and
  `ASSERT(x, n: INTEGER)`, `x` a BOOLEAN condition and `n` an
  implementation-defined exit/trap code — the report text explicitly
  leaves `n`'s interpretation to the implementation. voc follows this
  same two-arg form as a compiler-recognized special form gated behind
  its `-a` flag (on by default): on failure it prints "Assertion
  failure." (plus `n` if nonzero) and exits with `n` or 0. The one
  outlier is Wirth's own final/"Oberon-07" report, which has only the
  single-argument `ASSERT(b)` with no code parameter. Undecided whether
  poc should add `ASSERT`; if it does, voc's `ASSERT(x)` /
  `ASSERT(x, n: INTEGER)` two-arg form is the better precedent to match
  (also consistent with `HALT`'s existing exit-code convention) —
  possibly with an additional `ASSERT(x, msg: ARRAY OF CHAR)` overload
  taking a message string directly, which no surveyed dialect offers but
  would be more useful at a call site than an opaque integer code. Not
  scheduled to any phase yet.
  **Decided 2026-09-25** (user): poc has `ASSERT(x)` and `ASSERT(x, n)`;
  `doc/assert-survey.md` has the survey (which also covers Ofront, OfrontPlus,
  BlackBox, A2, obc, oo2c and OBNC) and the decision. One correction to the
  text above, found probing it: voc exits with 255, not 0, when there is no
  code or it is 0.

- **Open array dimension limit**: decided 2026-09-20 (Phase 11) - an open
  array type could have at most **8 open dimensions** (`Types.maxOpenDimensions`),
  an error where the ninth was written (fixture
  `semantic-reject-open-array-dimensions`), after a ninth open dimension on a
  parameter was found to crash poc with a run-time index error and on `NEW`
  to be accepted and do nothing. **Lifted 2026-09-25 (Phase 11 A17, the
  user's decision): no limit.** The four obstacles this entry used to list
  were dealt with as follows:
  1. `LLVMCodeGenerator.DopeVector` embedded `ARRAY 8 OF ValueText` (512
     bytes, in every `LocalBinding` and `DynamicType`); the lengths are now a
     list of nodes, shared when a `DopeVector` is copied and never changed
     once in one (dropping the outer length moves past the first node
     instead of shifting in place).
  2. A call's text was built in fixed buffers: one argument's lengths in a
     `LongText` (800 characters, overflowing at about 40 dimensions - probed:
     64 stopped poc with its own index trap in `Strcat`), the whole call in
     an `ArgsText` (4096). They are a `GrowingText`
     (`POINTER TO ARRAY OF CHAR`, doubled when full) now, which also lifts
     the bound on a call with very many ordinary arguments.
  3. `EmitProcSignature` named the hidden `.len<d>` parameters with
     `CHR(ORD("0") + dim)`, wrong from dimension 10 on (`%a.len:`); it uses
     `AppendLongInt` like the binding side.
  4. The checker rule, its message and `Types.maxOpenDimensions` are gone.
  voc's "Hard limit of 127 dimensions" (`OPB.Mod`) turned out to be only
  `LEN(a, n)`'s largest `n`; its types have no limit. Fixture
  `llvm-open-array-many-dimensions` (9, 20, 64, against voc under both
  size models; 400 probed by hand). Found on the way: voc gives a nested
  procedure garbage inner lengths for an enclosing multi-dimensional open
  array (vishap-bugs 12).

- **External procedure declaration syntax**: decided 2026-09-16, grammar/
  symbol-table side implemented in Phase 6 (2026-09-16) — a bracketed
  string-list attribute after `PROCEDURE`, body-less (`PROCEDURE ["C"]
  Name*(...): T;`, optionally `PROCEDURE ["C", "malloc"]
  AllocateBytes*(...): T;` to override the linkage name), per
  `AGENTS.md`'s "External procedures". Needed by Phase 6 for calling C
  functions on Linux/the BSDs, and by Phase 15 for VAX/VMS Calling
  Standard interop. Both backends' actual lowering is still Phase 8/14
  work - Phase 6 only parses the declaration and records its linkage
  info (`SymbolTable.ObjectDesc.externalConvention`/`externalName`).

- **`-OC`-equivalent elementary-type-size model**: resolved 2026-09-16 —
  `MemoryLayout.Mod` now parameterizes size/alignment/offset by two
  independent axes, target word size (32/64 bit, unchanged from Phase 4)
  and elementary-type size model (`sizeModelO2*`/`sizeModelOC*`), mirroring
  voc's own selectable `-O2` (classic 8/16/32/32-bit SHORTINT/INTEGER/
  LONGINT/SET) vs `-OC` (Component Pascal 16/32/64/64-bit) sizes. `REAL`,
  `LONGREAL`, `BOOLEAN`, `CHAR`, and `HUGEINT` don't vary by size model;
  under `-OC`, `LONGINT` and `HUGEINT` both end up 8 bytes but stay
  distinct named types (no aliasing/collapsing between them). poc does
  **not** get its own `-O2`/`-OC` CLI flag yet — `MemoryLayout.Mod`'s only
  caller is `Poc.Mod`'s `-dump-layout` debug/golden-file command (poc has
  no codegen yet), which has no real effect for a flag to govern until a
  backend exists, so it instead prints all four word-size × size-model
  combinations unconditionally. Revisit adding a real `-O2`/`-OC` flag once
  Phase 8's backend needs to pick one, or `.sym` interop with voc's
  `.../C/sym` requires it. When that flag is added, its `Usage` text
  should spell out the names rather than leaving them as bare letters —
  confirmed straight from voc's own `OPM.Mod` help text: `-O2` is
  "Original Oberon / Oberon-2", `-OC` is "Component Pascal". Match voc's
  own wording rather than inventing new phrasing.

- **Type guards in designators — two separate gaps**
  (`000-todo.org`'s bare "Type guards in designators?" line refers to
  both): (1) **mid-chain guards** (`v(T).field`, e.g. the report's own
  `t(CenterTree).subnode`) — resolved 2026-09-17. `Parser.Mod`'s
  `ParseDesignator` selector loop now folds `"(" Qualident ")"` in
  directly via a speculative `TryParseGuardSelector` (checkpoint the
  parser, commit to a `GuardSelector` node only when the closing `")"` is
  immediately followed by another selector token — the one shape
  Factor's own grammar, `Designator [ActualParameters]`, proves can
  never be `ActualParameters` instead, since a call's argument list is
  never followed by more selectors; every other shape rolls back
  unchanged, leaving the existing *terminal* guard-vs-call
  disambiguation, `LookupBareTypeName`/`CheckDesignatorExpr`, untouched).
  `CheckDesignator` (`SemanticActions.Mod`) applies the already-existing
  `CheckGuard`/`CheckExtensionApplicable` pair mid-chain via a new
  `GuardSelector` case, sharing a `ResolveTypeName` helper with
  `LookupBareTypeName` and `CheckWithGuard`. Three new conformance
  tests: `semantic-mid-chain-guard`, `semantic-reject-mid-chain-
  guard-not-type`, `semantic-reject-mid-chain-guard-not-extension`. Not
  revisited as part of this fix: several already-committed Phase 3/4
  procedures (`Types.Mod`'s `IsNumeric`/`EqualTypes`/`Extends*`/
  `ArrayCompatible*`/`AssignmentCompatible*`, `MemoryLayout.Mod`'s
  `DescriptorSize`, `SemanticActions.Mod`'s `CheckExtensionApplicable`)
  still bind a guarded value to a local variable before selecting a
  field off it, a workaround this fix makes optional but does not
  require removing — left alone deliberately, since simplifying eight
  call sites in the Appendix A predicates (the semantic crux of the
  whole front end) for a purely cosmetic win isn't worth the risk to
  already-tested code; revisit opportunistically, not as its own task.
  (2) **A qualified `WITH` variable** (`WITH M.v: T DO ...`) — resolved
  2026-09-17, but not the way it was first framed above (extend the
  shadow-`Insert` trick to narrow `M.v` too). Direct experiment against
  real voc found `WITH M.v: T DO` isn't a narrowing gap at all: voc
  rejects it outright (err 245, "guarded pointer variable may be
  manipulated by non-local operations; use auxiliary pointer variable"),
  because an imported module's exported pointer variable could be
  reassigned by any of *that* module's own procedures during the guarded
  body's execution — a real memory-safety hazard (the guard's narrowed
  type could no longer match what the variable actually points to), not
  a convenience gap. `Oberon2.pdf` §9.11 is silent on this either way
  (its grammar, `Guard = Qualident ":" Qualident`, happily allows the
  qualified spelling). Testing every shape directly against voc (not
  guessed at) showed this rejection is broader than just the qualified
  case — voc runs the same "could this be reassigned by a non-local
  operation" check for *every* pointer-typed WITH guard: it also rejects
  a VAR parameter of pointer type (an alias to the caller's storage) and
  a variable assigned by bare name inside some *other* `PROCEDURE`
  anywhere in the module (even one never called from the guarded body —
  a static check, not real call-graph reachability), while accepting a
  local variable, or a module-global, never assigned inside any
  `PROCEDURE` at all. `SemanticActions.Mod`'s `CheckWithGuard` now
  implements the same three rejections (see its own header comment for
  the full case-by-case table and the new `SymbolTable.ObjectDesc.
  isVarParam` field/`CollectProcAssignedNames` whole-module pre-pass that
  back it), deliberately the simpler, strictly *more conservative* half
  of voc's own rule (it doesn't special-case "except this same
  procedure's own straight-line code" the way voc does, so it also
  rejects that one narrow shape voc happens to allow — never less safe,
  only occasionally stricter). Four new conformance tests:
  `semantic-reject-with-qualified-guard`, `semantic-reject-with-var-
  param-guard`, `semantic-reject-with-global-reassigned`,
  `semantic-with-value-param-guard` (the accepting counterpart to the
  VAR-parameter rejection). The RECORD-typed guard case (VAR record
  parameter/receiver) is exempt from all of this and untouched - poc
  doesn't support RECORD guard variables at all yet regardless
  (`CheckExtensionApplicable`'s own header comment, PLAN.md Phase 6
  territory, pre-existing).

- **Predeclared "functions" in constant expressions — really two separate
  gaps, not one**: found 2026-09-17 while running the Phase 7 self-check
  milestone (`poc -check` against poc's own front-end source) —
  `ConstantEvaluator.Mod`'s own `maxHugeInt = MAX(LONGINT);` CONST
  declaration fails with "not a constant expression". `ConstantEvaluator.
  Mod`'s own header comment already documents its scope as deliberately
  narrow ("A ConstExpr's only possible leaves are literals, named constants
  ..., and TRUE/FALSE — never a variable, a call, or a selector"); no
  predeclared name was ever added to that set. Revisiting the framing
  (2026-09-17): `MAX`/`MIN`/`SIZE` are not really *calls* at all in the
  report's sense — their argument position holds a bare *type name*, not
  a value expression (`PredeclaredProcedures.Mod`'s own header comment
  already treats this as a distinct shape for ordinary, non-constant
  type-checking: "MAX/MIN/SIZE take a bare *type name* argument", handled
  by a small local `SymbolTable.Find` + typeClass check rather than
  through the injected `CheckExprProc`). Constant-folding this needs no
  general "evaluate a call's argument, then apply the function" machinery
  at all - just one more `ConstExpr` leaf shape (a predeclared name plus a
  bare type-name argument), resolved directly against a fixed, target-
  independent bound. This is a fundamentally smaller problem than folding
  a *value*-argument predeclared function (`ORD`/`ABS`/`CHR`/`ASH`/`CAP`/
  `ENTIER`/`LONG`/`ODD`/`SHORT`), which genuinely would need the general
  machinery (recursively evaluate the argument via `Evaluate`, then apply
  the function's own value transform) - that piece is deferred, not
  currently blocking anything found so far, and is real, separate,
  future work. (`ASH` was the first, Phase 9 step 10, 2026-09-19; the
  rest are Phase 11 step 2.)
  - `MAX(T)`/`MIN(T)` **implemented** 2026-09-17 for the integer family
    (`SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT`), `SET`, `CHAR` and
    `BOOLEAN` - the same argument set `PredeclaredProcedures.CheckMaxMin`
    already accepts for ordinary type-checking, minus `REAL`/`LONGREAL`
    (see below). `SHORTINT`/`INTEGER`/`LONGINT`/`SET`'s bounds are
    target-word-size-independent but do vary by elementary-type size
    model (`HUGEINT`/`CHAR`/`BOOLEAN` do not - always 8/1/1 bytes); see
    the `-O2`/`-OC` flags entry directly below for how that's resolved.
  - `MAX(REAL)`/`MAX(LONGREAL)`/`MIN(REAL)`/`MIN(LONGREAL)` **not**
    implemented - deliberately scoped out of the above. Unlike the
    integer family, the correct bound is an IEEE 754 largest-finite-value
    fact that should be verified against real voc's own actual behavior
    first (this project's standing "verify against voc before
    implementing" convention), not guessed at, and ties into the
    already-tracked correctly-rounded-float-formatting work (see
    `references.md`). Revisit alongside that, not as part of this pass.
    (Phase 9 step 8 lowered the run-time form; the `CONST` form was
    **implemented 2026-09-19, Phase 9 step 10** - see that step's account,
    including how a `.sym` carries it.)
  - `SIZE(T)` **implemented** 2026-09-17. Unlike `MAX`/`MIN`'s other
    bounds its result is genuinely target-dependent (word size and
    elementary-type size model - `MemoryLayout.Mod`'s own two axes).
    In practice `SIZE(T)` only works for a predeclared or imported `T`
    right now, never a type declared in the *same* module's own `TYPE`
    section - `CheckModuleBody` resolves `CONST` declarations before
    `TYPE` declarations unconditionally, regardless of their relative
    textual order (`000-todo.org`'s "Relax order of declarations" item,
    this file's own "Declaration order" entry below has the full
    voc-verified rationale), a real, concrete instance of that
    already-tracked gap found while testing this.
    Three new conformance tests: `semantic-const-max-min-size`,
    `semantic-reject-const-max-min-too-wide`, `semantic-reject-const-max-
    min-not-a-type`.
  - **`-O2`/`-OC` CLI flags added 2026-09-17** (`Poc.Mod`), addressing
    the "poc has no real `-O2`/`-OC` CLI flag yet" gap the two bullets
    above originally had to work around by assuming `-O2`. Select the
    elementary-type size model (`MemoryLayout.sizeModelO2`/`sizeModelOC`)
    that `MAX(T)`/`MIN(T)`/`SIZE(T)` (and, as a direct consequence,
    ordinary integer-literal typing - `IntegerLiteralType` shares the
    exact same bounds, see `ConstantEvaluator.Mod`'s own header comment)
    fold against; default `-O2`, a later flag wins if given more than
    once, matching `-output-dir`'s own precedent. Implemented as a
    `ConstantEvaluator.SetSizeModel*` exported setter (module `VAR`s,
    recomputed on call) rather than threading a size-model parameter
    through `Evaluate*`'s whole mutually-recursive call graph and every
    one of `SemanticActions.Mod`'s nine call sites - mirrors
    `Diagnostics.fileName*`/`errorCount*`'s own existing "module `VAR`
    set once per compilation, read everywhere" pattern. `SIZE(T)` still
    always uses `MemoryLayout.wordSize32` - there is still no word-size
    (32/64-bit) flag, since nothing before a real backend (Phase 8+)
    makes that axis observable the way `-O2`/`-OC`'s differing
    `SHORTINT`/`INTEGER`/`LONGINT`/`SET` ranges now are. `-dump-layout`
    (Phase 4) is intentionally unaffected - it keeps printing all four
    word-size x size-model combinations regardless of `-O2`/`-OC`, since
    it is a golden-file testing surface for `MemoryLayout.Mod` itself,
    not a preview of one selected target.
    **Found, not fixed, while verifying this**: `ModuleInterface.Mod`'s
    `FormatInt` (used by `-emit-interface` to print a folded integer
    `CONST`'s value) negates its argument (`v := -v`) to build the digit
    string, which overflows - and silently produces just `"-"` with no
    digits - for any value at exactly a `LONGINT`'s two's-complement
    minimum (the same magnitude-has-no-positive-representation asymmetry
    `ConstantEvaluator.Mod`'s own `minHugeInt`/`minShortInt`/etc. already
    had to route around with a computed `-maxX - 1`, never applied here).
    Pre-existing and already reachable via `MIN(HUGEINT)` before this
    session (confirmed: unaffected by `-O2`/`-OC`, since `HUGEINT`'s
    bound doesn't vary by size model) - `-OC` just makes it reachable via
    `MIN(LONGINT)` too, since `LONGINT` is 8 bytes under `-OC`, the same
    width as `HUGEINT`. Only affects `-emit-interface`'s printed `.sym`
    text for this one exact boundary value; `-check`'s type-checking of
    the identical `CONST` is unaffected (confirmed correct via the
    existing `semantic-const-max-min-size` test, which already exercises
    `MIN(HUGEINT)` through `-check`, never `-emit-interface`). Not
    scheduled to any phase yet.

- **Constant arithmetic doesn't re-derive its result's minimal type from
  the computed value**: found 2026-09-17 while testing the `MAX(T)`/
  `MIN(T)` work above. `ConstantEvaluator.EvaluateNumericOp` types an
  arithmetic result via `Types.WiderOf(l.type, r.type)` alone (purely
  rank-based, matching Appendix A's arithmetic-operator table), never by
  re-examining the computed value the way `IntegerLiteralType` already
  does for a bare literal token. So `CONST TooWide = MAX(SHORTINT) + 1;`
  (value 128) stays `SHORTINT`-typed in poc, even though 128 does not fit
  `SHORTINT`'s own range - but real voc (confirmed 2026-09-17) rejects
  `s := TooWide` (`s: SHORTINT`) with "incompatible assignment", meaning
  voc *does* re-derive the minimal type from 128 itself. `Oberon2.pdf`
  §5's wording ("the type of an integer constant is the minimal type to
  which the constant value belongs") is about "an integer constant"
  generally, arguably not just a literal token, which would support
  voc's broader reading. Not fixed - found by a test, not by design
  review, and deliberately routed around rather than papered over (see
  `semantic-reject-const-max-min-too-wide`'s own header comment for how).
  Would need `EvaluateNumericOp` (and presumably `EvaluateUnary`'s
  negation case) to re-run something like `IntegerLiteralType`'s own
  digit-range logic against the computed value, not just the operand
  types - worth doing, but a separate, general `ConstantEvaluator.Mod`
  correctness fix, not specific to `MAX`/`MIN`. **Resolved 2026-09-19,
  Phase 9 step 10**: every integer operation a constant expression folds
  re-derives its result's minimal type from the value (voc's `SetIntType`),
  in `CONST` declarations and in ordinary expressions alike; `CONST TooWide
  = MAX(SHORTINT) + 1` is now an INTEGER, and `s := TooWide` is rejected.

- **Declaration order: voc relaxes CONST/TYPE/VAR *section* order, never
  reference order** (`000-todo.org`'s "Relax order of declarations", the
  general form of the `SIZE(Rec)` finding two entries above): tested
  directly against real voc 2026-09-17 with a battery of targeted
  fixtures, not just the one accepting case already known. Two
  independent findings, easy to conflate but not the same thing:
  - voc accepts `CONST`/`TYPE`/`VAR` *sections* in any order, repeated and
    interleaved arbitrarily many times in a single `DeclSeq`
    (`CONST A; TYPE Rec; CONST B = A+1; TYPE Rec2; VAR ...` all compiles) -
    which is `Oberon2.pdf`'s own grammar (§10, `DeclarationSequence =
    {CONST ... | TYPE ... | VAR ...} {ProcedureDeclaration ...}`), not an
    extension (corrected 2026-09-25: this entry used to call it one, taking
    the grammar for Oberon-07's, which does fix one optional section each,
    in `CONST`, `TYPE`, `VAR` order). `PROCEDURE`
    declarations, though, must still come after every `CONST`/`TYPE`/`VAR`
    section - voc rejects a `TYPE`/`VAR` section appearing after the first
    `PROCEDURE` (`err 41 END missing`), matching the grammar's own
    `{ProcedureDecl ";" ...}` tail position.
  - Despite that, voc still enforces strict declare-before-use, single-pass
    name resolution throughout - confirmed rejected: a `CONST` forward-
    referencing a later `CONST` in the same section, a `TYPE` forward-
    referencing a later `TYPE` by value (inline field, no pointer), a
    `CONST` referencing a `TYPE` declared in a *later* section, and a
    procedure body referencing a `CONST` or another procedure declared
    later (the latter needs the standard `PROCEDURE^` forward declaration,
    same as poc already requires). The only two forward-reference
    exceptions in the entire language are the two `Oberon2.pdf` already
    documents and poc already implements: a `POINTER`'s own inline base
    type, and `PROCEDURE^`.
  So `SIZE(Rec)` (two entries above) works in voc not because voc allows a
  `CONST` to forward-reference a `TYPE`, but because that fixture happened
  to declare `TYPE Rec` *before* the `CONST` referencing it - a section-
  order relaxation, not a reference-order one. **Decided** (discussion
  2026-09-17): poc should match this precisely - no new forward-reference
  mechanism, just resolve `CONST`/`TYPE`/`VAR` declarations as one linear
  pass over the `DeclSeq` in actual textual order (regardless of which
  keyword introduces each one), instead of `CheckModuleBody`'s current
  three separate whole-section passes (`ResolveConstDecls` then
  `ResolveTypeDecls` then `ResolveVarDecls`). `Parser.Mod`'s `ParseDeclSeq`
  already parses interleaved/repeated `CONST`/`TYPE`/`VAR` sections
  correctly (its outer `LOOP` accepts any of the three keywords, any
  number of times) - the gap is that it then sorts every declaration into
  three separate `SyntaxTree.DeclSeqNode` lists (`constDecls`/`typeDecls`/
  `varDecls`), discarding the cross-section textual order `CheckModuleBody`
  would need to walk them in one pass.

  **Implemented 2026-09-17.** `SemanticActions.Mod`'s old
  `ResolveConstDecls`/`ResolveTypeDecls`/`ResolveVarDecls` (three whole-
  section passes) are replaced by `ResolveDeclSeq`: a `PredeclareTypeNames`
  pre-pass (unchanged in spirit - registers every `TYPE` name across the
  whole `DeclSeq` up front, `obj.pendingTypeNode` set but nothing resolved
  yet, so the `POINTER`-base exception still works regardless of source
  order), then one merged pass dispatching to `ResolveOneConstDecl`/
  `ResolveOneTypeDecl`/`ResolveOneVarDecl` in actual textual order - a
  three-way merge over the three still-separately-typed lists (each
  already in its own order), keyed on each node's own `line`/`column`
  (`SyntaxTree.DeclSeqNodeDesc`'s own header comment has the rationale for
  merging rather than restructuring the AST into one polymorphic list).
  `SyntaxTree.Mod`, `ModuleInterface.Mod`, `Poc.Mod` (`-dump-layout`) are
  untouched - none of them cared about cross-kind order.

  **Extended 2026-09-25 (Phase 11 A22, with the user):** sections may now
  also follow procedures, poc's extension; declare-before-use is unchanged.
  `SemanticActions.CheckDeclarations` merges the procedures into the same
  textual-order walk. `doc/language-extensions.md`, "Declarations after
  procedures", has what a program can observe.

  Two real correctness gaps surfaced while implementing this, both fixed
  alongside it, not deferred: the merge makes it newly possible for an
  *earlier* `POINTER`'s own base resolution to eagerly resolve some
  *later* type as a side effect, before that type's own textual turn in
  the pass - `SemanticActions.ResolveQualidentType`'s existing forward-
  reference check was gated behind `obj.pendingTypeNode.line` (cleared to
  `NIL` the moment eager resolution happens) and its first branch
  (`obj.type # NIL`) already short-circuited past the check entirely once
  that happened, so this was actually a **pre-existing** bug, reachable
  even before this change (confirmed with a standalone repro not
  involving `CONST`/`VAR` merging at all: `TYPE P = POINTER TO PDesc; VAR
  r: PDesc; TYPE PDesc = ...;` - poc accepted it, real voc rejects it).
  Fixed by adding `SymbolTable.ObjectDesc.declLine*/declColumn*` (an
  Object's own declaration site, set once by `Insert`, never cleared) and
  checking that instead, before the `obj.type # NIL` fast path rather
  than after; `ConstantEvaluator.LookupBareTypeName` (`MAX`/`MIN`/`SIZE`'s
  own separate lookup, can't import `SemanticActions.Mod`) needed the
  identical fix for the same reason, applied only to unqualified
  (same-module) references - a qualified `M.T` reference's `declLine` is
  a line number in that other, already-fully-checked file's own text, not
  comparable to this module's `expr.line` at all; missing that qualifier
  guard in `SemanticActions.ResolveQualidentType`'s own first attempt at
  this fix broke `semantic-reject-readonly-import-field` (a legitimate
  cross-module `VAR t: trees.Tree` wrongly flagged "forward reference"),
  caught immediately by the conformance suite and fixed by adding the
  guard. Separately, moving `TYPE`'s `CheckExportMark` (the `-` mark
  validity check) into the new up-front pre-declare pass initially
  reported it out of textual order relative to `CONST`/`VAR`'s own
  export-mark errors (caught by `semantic-reject-readonly-mark`'s two
  expected errors coming back swapped); fixed by deferring that call to
  `ResolveOneTypeDecl` instead, so it fires at each type's own turn in the
  merged pass like every other diagnostic, leaving only name registration
  itself in the pre-declare pass. Three new conformance tests:
  `semantic-decl-order-const-refs-later-section-type` (the original
  `SIZE(Rec)` motivating case), `semantic-decl-order-interleaved-sections`
  (`CONST`/`TYPE`/`CONST`/`VAR` in one `DeclSeq`), `semantic-reject-decl-
  order-const-forward-type` (the still-illegal genuine forward case). All
  94 conformance tests pass; the Phase 7 self-check sweep (`000-todo.org`)
  still self-checks the same 8 modules clean as before, unaffected.
