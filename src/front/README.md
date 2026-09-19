# src/front

Backend-agnostic front end: lexer, parser, symbol table, type checking,
module interface handling. See `PLAN.md` Phases 1-7 for the module-by-module
build order (`Lexer.Mod`, `Parser.Mod`, `SymbolTable.Mod`, `Types.Mod`,
etc.).

- `Diagnostics.Mod` (Phase 1): error reporting with source positions.
- `Lexer.Mod` (Phase 1): scanner for the full Oberon-2 vocabulary (§3).
- `SyntaxTree.Mod` (Phase 2): untyped AST node types for Appendix B,
  related via record extension (`StatementNode`, `ExprNode`, `TypeNode`
  are each an extensible family).
- `SemanticActions.Mod` (Phase 2 tree-construction; Phase 3/4/5/6
  resolution): the New* procedures are Phase 2's pure-builder stub,
  invoked by the parser as it recognizes each production. CheckModule*
  and its helpers are a separate pass over the finished tree, run by
  `Poc.Mod`'s `-check`/`-dump-layout` modes, that resolves CONST, TYPE,
  VAR (Phase 5), and (from Phase 6) PROCEDURE declarations against
  SymbolTable.Mod/Types.Mod/ConstantEvaluator.Mod/
  PredeclaredProcedures.Mod. Phase 4 adds array/record/procedure-type
  resolution and an early-registration scheme for named POINTER/RECORD
  declarations (see ResolveType's header comment) so self- and
  mutually-referential linked structures resolve correctly despite the
  forward-declaration ordering rules. Phase 5 adds a second, parallel
  Appendix A expression-compatible table (CheckExpr and its helpers -
  computing a static type for any expression, not just a compile-time
  constant, unlike ConstantEvaluator.Mod), designator/selector
  resolution with §8.1's auto-deref rule, and a terminal-only type-guard
  `v(T)`/`IS` disambiguation (see its own header comment for the
  Parser.Mod grammar gap this works around). Phase 6 finishes procedure/
  statement checking: `ResolveProcDecls` (plain and type-bound procedure
  declarations, one pass in textual order - unlike TYPE's two-pass
  forward machinery, since Oberon-2 gives procedures an explicit
  forward-reference escape hatch already), receiver resolution (§10.2's
  exactly-two-shapes rule), override checking, `CheckArguments`
  (Appendix A "matching formal parameter lists" - `Types.
  ArrayCompatible*`/`ProcedureTypesMatch*`'s first real callers), `v.P`/
  `r.P^` dispatch folded into `CheckDesignator`'s existing selector walk,
  `WITH` (reusing Phase 5's guard-applicability pair outright; since
  Phase 9 step 6 all three also apply to a VAR parameter of record type,
  via `lastDesignatorIsVarParam`), and
  dispatch to `PredeclaredProcedures.Mod` for §10.3's builtins. Two
  explicit, narrower scope boundaries: a function procedure's "must
  contain a return statement" check is shallow (no `BEGIN` at all is
  rejected, not a full return-reachability analysis), and `r.P^`
  base-dispatch is a narrow special case grafted onto
  `DereferenceSelector`, not a generalization of it.
- `PredeclaredProcedures.Mod` (Phase 6): Oberon2.pdf §10.3's full
  predeclared-procedure vocabulary (13 function procedures, 7 proper
  procedures - confirmed against the report's own table, which has no
  `ASSERT` entry). Cannot import SemanticActions.Mod (that would be
  circular - SemanticActions.Mod is the one dispatching in here), so
  `CheckCall*` takes `CheckExpr`/`CheckDesignator` as procedure-typed
  parameters instead, the standard way to break a mutual-dependency
  cycle between two single-pass-compiled modules; see its own header
  comment for why a bare-type-name lookup (`MAX`/`MIN`/`SIZE`'s argument
  shape) is duplicated locally rather than injected as a third
  procedure, and why `SIZE(T)` type-checks to `INTEGER` without
  computing `T`'s actual byte count (a backend/codegen concern this
  phase, semantic analysis only, does not reach).
- `Parser.Mod` (Phase 2): recursive-descent parser, one procedure per
  Appendix B production. Documents two syntax-only simplifications
  (the qualident/selector and type-guard/call ambiguities) that later
  phases resolve once real symbol information exists - Phase 5 resolves
  the second one for a *terminal* guard/`IS`; a guard followed by a
  chained selector (`v(T).field`) still needs a grammar change here,
  not undertaken by Phase 6 either. Untouched by Phase 3: semantic
  resolution runs as a separate post-parse pass (see
  SemanticActions.Mod) rather than growing into the parser itself. Phase
  6 adds one small, unambiguous grammar addition instead: a `"["` right
  after `PROCEDURE` introduces the already-decided external-procedure-
  declaration attribute (AGENTS.md, "External procedures").
- `Types.Mod` (Phase 3 basic types; Phase 4 composite types; Phase 5/6
  Appendix A primitives): type representations - basic types (§6.1) and
  their numeric inclusion hierarchy, plus array, record, procedure, and
  pointer forms (§6.2-6.5), following the same record-extension pattern
  SyntaxTree.Mod uses for its node families. Also defines `HUGEINT`, a
  Peaseblossom language extension (not in §6.1) adopted from voc's own
  identically-named extension - see AGENTS.md's "Language extensions
  beyond Oberon2.pdf". Stores no size/alignment/offset information
  itself (that depends on the target word size - see MemoryLayout.Mod).
  Phase 5 adds `AssignmentCompatible*`/`IsInteger*` (broadly-reusable
  Appendix A predicates, alongside Phase 4's `Extends*`/
  `ArrayCompatible*`), `FindField*` (a "." selector's field lookup,
  including inherited fields via the base-type chain), and `NilType*` (a
  singleton giving `NIL` a real static type). Phase 6 adds
  `EqualTypes*` (Appendix A's own broader "equal types" - two
  independently-written open-array formal types are never the *same*
  type by pointer identity, but the report's "matching formal parameter
  lists" says they should still match, a real gap `ParamListsMatch` now
  closes), `Method*`/`AddMethod*`/`FindMethod*` (`RecordType`'s
  counterpart to `Field*`/`AddField*`/`FindField*` for §10.2's
  type-bound procedures), and `PredeclaredProcedureType*` (a shared
  marker `Type` identifying a `SymbolTable.Object` as one of §10.3's
  predeclared procedures).
- `SymbolTable.Mod` (Phase 3): Object/Scope model (§4) - insertion,
  lookup, nested scopes. Semantics-free by design; knows nothing about
  qualidents, constant expressions, or forward POINTER references.
  Phase 6 adds `isForwardProc*` (a `procClass` Object's counterpart to
  `pendingTypeNode`/`resolving`, for `"PROCEDURE^"` forward
  declarations) and `externalConvention*`/`externalName*` (linkage info
  for an external procedure declaration, so a future backend can find it
  without re-walking the AST); the module body also `Insert`s all 20 of
  §10.3's predeclared-procedure names into `Universe`.
- `ConstantEvaluator.Mod` (Phase 3): compile-time constant folding (§5)
  over the basic types, including numeral text-to-value conversion
  (deferred here from Lexer.Mod) and the six relations, BOOLEAN and SET
  operators, and the numeric inclusion hierarchy.
- `MemoryLayout.Mod` (Phase 4): size/alignment/field-offset computation
  for Types.Mod's representations, parameterized by an explicit target
  word size (4 or 8 bytes) and, since 2026-09-16, an elementary-type size
  model (`sizeModelO2*`/`sizeModelOC*`, mirroring voc's own `-O2`/`-OC`
  SHORTINT/INTEGER/LONGINT/SET widths - PLAN.md's "Open design
  questions") on every call rather than cached on a Type - see its own
  header comment for the alignment-capping rule and the open-array
  dope-vector convention. `Poc.Mod`'s `-dump-layout` is its golden-file
  testing surface, standing in for the ASSERT-based fixtures PLAN.md
  envisioned, since poc has no codegen yet to run one through; it prints
  all four word-size x size-model combinations unconditionally, since
  poc has no `-O2`/`-OC` CLI flag of its own yet.
