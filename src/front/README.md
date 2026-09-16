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
- `SemanticActions.Mod` (Phase 2): tree-construction actions invoked by
  the parser; a pure-builder stub until Phase 3 adds real scope
  population, resolution, and type checking to these same procedures.
- `Parser.Mod` (Phase 2): recursive-descent parser, one procedure per
  Appendix B production. Documents two syntax-only simplifications
  (the qualident/selector and type-guard/call ambiguities) that later
  phases resolve once real symbol information exists.
