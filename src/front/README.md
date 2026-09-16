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
- `SemanticActions.Mod` (Phase 2 tree-construction; Phase 3 resolution):
  the New* procedures are Phase 2's pure-builder stub, invoked by the
  parser as it recognizes each production. CheckModule* and its helpers
  are Phase 3: a separate pass over the finished tree, run by `Poc.Mod`'s
  `-check` mode, that resolves CONST and TYPE declarations against
  SymbolTable.Mod/Types.Mod/ConstantEvaluator.Mod.
- `Parser.Mod` (Phase 2): recursive-descent parser, one procedure per
  Appendix B production. Documents two syntax-only simplifications
  (the qualident/selector and type-guard/call ambiguities) that later
  phases resolve once real symbol information exists. Untouched by
  Phase 3: semantic resolution runs as a separate post-parse pass (see
  SemanticActions.Mod) rather than growing into the parser itself.
- `Types.Mod` (Phase 3): type representations - complete for the basic
  types (§6.1) and their numeric inclusion hierarchy; array, record, and
  procedure forms are Phase 4/6 additions, following the same
  record-extension pattern SyntaxTree.Mod uses for its node families.
- `SymbolTable.Mod` (Phase 3): Object/Scope model (§4) - insertion,
  lookup, nested scopes. Semantics-free by design; knows nothing about
  qualidents, constant expressions, or forward POINTER references.
- `ConstantEvaluator.Mod` (Phase 3): compile-time constant folding (§5)
  over the basic types, including numeral text-to-value conversion
  (deferred here from Lexer.Mod) and the six relations, BOOLEAN and SET
  operators, and the numeric inclusion hierarchy.
