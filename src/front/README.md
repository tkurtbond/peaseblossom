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
- `SemanticActions.Mod` (Phase 2 tree-construction; Phase 3/4 resolution):
  the New* procedures are Phase 2's pure-builder stub, invoked by the
  parser as it recognizes each production. CheckModule* and its helpers
  are a separate pass over the finished tree, run by `Poc.Mod`'s
  `-check`/`-dump-layout` modes, that resolves CONST and TYPE
  declarations against SymbolTable.Mod/Types.Mod/ConstantEvaluator.Mod.
  Phase 4 adds array/record/procedure-type resolution and an
  early-registration scheme for named POINTER/RECORD declarations (see
  ResolveType's header comment) so self- and mutually-referential linked
  structures resolve correctly despite the forward-declaration ordering
  rules.
- `Parser.Mod` (Phase 2): recursive-descent parser, one procedure per
  Appendix B production. Documents two syntax-only simplifications
  (the qualident/selector and type-guard/call ambiguities) that later
  phases resolve once real symbol information exists. Untouched by
  Phase 3: semantic resolution runs as a separate post-parse pass (see
  SemanticActions.Mod) rather than growing into the parser itself.
- `Types.Mod` (Phase 3 basic types; Phase 4 composite types): type
  representations - basic types (§6.1) and their numeric inclusion
  hierarchy, plus array, record, procedure, and pointer forms (§6.2-6.5),
  following the same record-extension pattern SyntaxTree.Mod uses for
  its node families. Also defines `HUGEINT`, a Peaseblossom language
  extension (not in §6.1) adopted from voc's own identically-named
  extension - see AGENTS.md's "Language extensions beyond Oberon2.pdf".
  Stores no size/alignment/offset information itself (that depends on
  the target word size - see MemoryLayout.Mod).
- `SymbolTable.Mod` (Phase 3): Object/Scope model (§4) - insertion,
  lookup, nested scopes. Semantics-free by design; knows nothing about
  qualidents, constant expressions, or forward POINTER references.
- `ConstantEvaluator.Mod` (Phase 3): compile-time constant folding (§5)
  over the basic types, including numeral text-to-value conversion
  (deferred here from Lexer.Mod) and the six relations, BOOLEAN and SET
  operators, and the numeric inclusion hierarchy.
- `MemoryLayout.Mod` (Phase 4): size/alignment/field-offset computation
  for Types.Mod's representations, parameterized by an explicit target
  word size (4 or 8 bytes) on every call rather than cached on a Type -
  see its own header comment for the alignment-capping rule and the
  open-array dope-vector convention. `Poc.Mod`'s `-dump-layout` is its
  golden-file testing surface, standing in for the ASSERT-based fixtures
  PLAN.md envisioned, since poc has no codegen yet to run one through.
