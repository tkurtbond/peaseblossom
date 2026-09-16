# Peaseblossom

Peaseblossom is a from-scratch Oberon-2 compiler. The compiler executable is
named **`poc`** (Peaseblossom Oberon Compiler).

## Target backends

Two desired outcomes, i.e. two backends sharing a common front end:

1. An **LLVM-based** backend, for 32-bit and 64-bit machines. Beyond
   Linux, this backend must also run on **NetBSD, OpenBSD, and FreeBSD**
   — a portability goal, not just a word-size one, so the runtime's
   OS-facing layer (I/O, process/argv setup) needs to be written with all
   four Unix-likes in mind rather than assuming Linux-only libc/syscall
   behavior.
2. A **bespoke backend** targeting **VAX/VMS 5.5-2** — a specific, dated
   VMS release on the VAX architecture (pre-dating OpenVMS/Alpha). LLVM
   does not target VAX, so this backend cannot reuse the LLVM path and
   needs its own code generator.

This implies the front end (lexer, parser, AST, semantic analysis/type
checking) should be kept backend-agnostic from the start, with codegen
factored out behind a clean interface, since the two backends have nothing
in common at the instruction-selection level.

## Language specification

Two copies of the Oberon-2 report by H. Mössenböck and N. Wirth are kept
locally under `~/Reference/Computer/Languages/Oberon/`, along with
`pdftotext` extracts (`-layout` preserves columns/tables; `-no-layout` is
plain reading order):

- `Oberon2-Report.pdf` / `Oberon2-Report-{layout,no-layout}.text` — the
  original ETH tech report, dated October 1993 in the body text. Typeset by
  the Oberon system itself; the PDF is a frozen 2015 Ghostscript conversion
  (creation date == mod date, never touched again).
- `Oberon2.pdf` / `Oberon2-{layout,no-layout}.text` — a later revision.
  Authored in WriteNow, first exported to PDF in 2007, **modified again in
  2022**. Content-wise it refines the 1993 text in several places, all in
  one direction (never reversed):
  - Pointers are stated to initialize to NIL by default (§6.4).
  - Forward declaration / redefinition parameter lists must be "identical",
    not just "match" (§10, §10.2) — a stricter, clearer rule.
  - The `Trees` example module's `Init(t: Tree)` (VAR-parameter
    initializer) is replaced by `NewTree(): Tree` (allocating function) —
    an API redesign, updated consistently in both the main example and the
    Appendix D4 browser-output example.
  - The array-compatibility rule (Appendix A) is tightened: `ARRAY OF CHAR`
    parameter matching a string requires the formal to be a **value**
    parameter.
  - `HALT` is simplified from two overloads (`HALT(n)`, `HALT(n, code)`) to
    one (`HALT(x)`).
  - Assorted prose smoothing (e.g. "must be left via a return statement"
    instead of "require the presence of a return statement").

**`Oberon2.pdf` is the authoritative spec for Peaseblossom.** Use
`Oberon2-Report.pdf` only as historical background or when explicitly
comparing the two. Neither file carries a printed revision number, so when
in doubt about a specific rule, treat `Oberon2.pdf`'s wording as
controlling and check the PDF metadata (`pdfinfo`) if provenance matters
again.

## Reference implementation: Vishap Oberon (voc)

Vishap Oberon is used as the reference/bootstrap implementation while
building `poc` — for cross-checking semantics, running comparison test
programs, and (potentially) bootstrapping.

- Installed binary: `/usr/local/sw/versions/voc/git/bin/voc` (and
  `showdef`). Add to `PATH` to use directly.
- Installed libraries/symbol files:
  `/usr/local/sw/versions/voc/git/lib`,
  `/usr/local/sw/versions/voc/git/2/{include,sym}` (O2 size model),
  `/usr/local/sw/versions/voc/git/C/{include,sym}` (OC / Component Pascal
  size model).
- Read-only git clone of voc's source (remote:
  `github.com/vishapoberon/compiler.git`):
  `/usr/local/sw/src/lang/Oberon/vishap/voc`
  - `src/compiler/OP{B,C,M,P,S,T,V}.Mod` — the compiler passes.
  - `src/library/{misc,ooc,ooc2,oocX11,pow,s3,ulm,v4}` — bundled libraries.
  - `src/runtime`, `src/test`, `src/tools`.
  - `doc/*.md` — Compiling.md, ctags.md, Features.md, Files.md, History.md,
    Installation.md, Porting.md, Winstallation.md.
- Version as of 2026-09-16: "Oberon-2 compiler v2.1.0 [2026/09/16] for gcc
  LP64 on fedora", based on Ofront (J. Templ).

Voc's own extensions beyond the report, documented in `doc/Features.md` —
these are Vishap-specific, not part of the Oberon-2 standard, and should
not be assumed required for Peaseblossom unless deliberately adopted for
compatibility:

- Selectable elementary type sizes via `-O2` (default: 8/16/32/32 bit
  SHORTINT/INTEGER/LONGINT/SET — the classic Oberon-2 sizes) vs. `-OC`
  (Component Pascal sizes: 16/32/64/64 bit). `tools/bootstrap/stage0`
  builds poc itself with `-OC` — a codegen-only flag, not a source-syntax
  extension, chosen so poc's own `LONGINT` variables get 8 real bytes of
  storage (needed by `Types.Value.intVal` to hold a full-range `HUGEINT`
  constant without wrapping; see "Language extensions beyond Oberon2.pdf"
  below). This doesn't relax the strict-Oberon2.pdf-syntax constraint on
  poc's own source (see `PLAN.md`, "Bootstrap terminology") — only the
  build flag changed, not what poc's own source is allowed to write.
- Extra `HUGEINT` type (64-bit), available even under `-O2`. Peaseblossom
  adopted this one outright as its own extension — see "Language
  extensions beyond Oberon2.pdf" below.
- `SYSTEM.ADDRESS` type, used in place of `LONGINT` for
  `SYSTEM.ADR/BIT/GET/PUT/MOVE`, since `LONGINT` can no longer be assumed
  address-sized on all targets.
- `SYSTEM.INT8/16/32/64` and `SYSTEM.SET32/64` fixed-size types.
- Read-only **value** parameters via a `-` marker (Oakwood guideline 5.13)
  — beyond what either report PDF documents (they only allow `-` on
  record fields / module-level exported identifiers).
- Pointers initialize to NIL by default (`-p`, on by default) — this one
  *does* match `Oberon2.pdf`, corroborating that it's the newer report.
- `-a` (assert halt), `-t` (type guard halt), `-x` (index range halt) on
  by default; `-r` (range check halt) off by default.

`voc` CLI usage: `voc options {files {options}}`. Options before the first
filename set defaults for all files; options after a filename apply only
to that file. Repeating a flag toggles it.

### Known voc bugs affecting poc's own source

Bugs (not spec deviations) found in voc 2.1.0 while writing poc's own
source, worth knowing before puzzling over a bogus-looking error again
during Stage 0/1/2 bootstrapping:

- **Self-recursive call from inside a `WITH` branch, misdiagnosed as
  "incompatible assignment"**: if procedure `P` calls itself from inside
  one of `P`'s own `WITH v: T DO ... END` branches, voc rejects the call
  even when the argument's type is fine — reproduced with a minimal
  `POINTER`/`WITH`/self-call example (not just in poc's own source).
  Calling a *different* procedure from inside the same `WITH` branch is
  unaffected; only literal self-recursion from inside one's own `WITH`
  triggers it. Workaround: save whatever the recursive call needs into a
  local variable inside the `WITH` branch, then make the recursive call
  after the `WITH` statement ends. See
  `src/front/SemanticActions.Mod`'s `ResolveType` for a real instance.

## Language extensions beyond Oberon2.pdf

### HUGEINT (implemented)

An 8-byte signed integer, predeclared alongside `Oberon2.pdf`'s own basic
types (§6.1). Adopted directly from voc's identically-named, identically-
sized extension (see "Vishap Oberon (voc)" above) rather than inventing a
new name — an Oberon-2 programmer reaching for "an integer wider than
LONGINT" already expects this spelling. Implemented in `Types.Mod`
(`HugeInt*`, ranked in the numeric inclusion hierarchy directly below
`REAL` — `LONGREAL ⊇ REAL ⊇ HUGEINT ⊇ LONGINT ⊇ INTEGER ⊇ SHORTINT`, since
every integer type ranks below every real type regardless of width, the
same reason `LONGINT` already ranks below `REAL`), `SymbolTable.Mod`
(predeclared identifier), and `ConstantEvaluator.Mod` (`IsIntegerType`/
arithmetic folding). Not yet exercisable end-to-end: literal typing
doesn't yet pick `HUGEINT` for large numerals (needs Phase 4's
`MemoryLayout.Mod` to give basic types real bit widths to check literals
against), and there's no `VAR`/parameter syntax yet (Phase 5/6) to declare
a `HUGEINT`-typed value directly — today it's reachable only as a `TYPE`
alias target (see `test/conformance/semantic-hugeint-type`).

### External procedures

`Oberon2.pdf` defines no mechanism for calling procedures implemented in
another language, only the low-level `SYSTEM` module (Appendix C) for
memory/register access. Peaseblossom needs one anyway, so poc's language
has a deliberate, documented extension for declaring an **external
procedure** — analogous in spirit to how this file documents voc's own
extensions (see "Vishap Oberon (voc)" above), except this one is
Peaseblossom's own.

- **Simplest case**: calling external C functions on Linux/Unix-like
  targets (including the NetBSD/OpenBSD/FreeBSD portability goal above) —
  the C calling convention is what LLVM (and `llc`/`clang`) already speak
  natively, so the LLVM backend mostly just needs to emit a `declare` for
  the external symbol and call it.
- **VAX/VMS target**: VMS has its own well-defined, documented **VMS
  Calling Standard**. The VAX/VMS backend will need to implement that
  calling convention for any declared external procedure — this is more
  work than the LLVM/C case, but the convention itself is well-specified
  and stable.
- **Decided (2026-09-16), implemented (2026-09-16, Phase 6's grammar/
  `SymbolTable.Mod`/`SemanticActions.Mod` side): a bracketed string-list
  attribute right after the `PROCEDURE` keyword, following Component
  Pascal/BlackBox's own precedent for declaring foreign (e.g. Win32 DLL)
  procedures** — `PROCEDURE ["C"] Name*(...): T;` with **no body** (the
  missing body is what marks the declaration external; a body-less
  `PROCEDURE` with no such attribute stays a syntax error, same as
  today). The first string names the calling convention (`"C"` for
  Phase 8's LLVM/C-interop case, `"VMS"` for Phase 10's VMS Calling
  Standard case — both accepted now, even though nothing consumes
  `"VMS"` until Phase 10). An optional second string overrides the
  external linkage name, since Peaseblossom's own naming convention (see
  "Naming feedback" — descriptive, often-long identifiers) routinely
  won't match a terse external symbol like `malloc` or `printf`:
  `PROCEDURE ["C", "malloc"] AllocateBytes*(size:
  LONGINT): SYSTEM.ADDRESS;`. Without the second string, the external
  symbol is the procedure's own Oberon identifier verbatim
  (`SymbolTable.ObjectDesc.externalName`). This interacts with the VAX
  backend's 31-character name-mangling requirement (Phase 10, below): an
  external procedure's linkage name is emitted **verbatim, never
  mangled** — it has to match the real external symbol, unlike poc's own
  internally-generated names. Both backends' actual lowering is still
  Phase 8/10 work; Phase 6 only records the linkage info
  (`SymbolTable.ObjectDesc.externalConvention`/`externalName`) for a
  later backend to consume.

## Project state

As of 2026-09-16, `PLAN.md` lays out the full phased roadmap (directory
layout, bootstrap terminology, phase-by-phase build order). Phase 0
(scaffolding + conformance-test harness) and Phase 1 (`Lexer.Mod`,
`Diagnostics.Mod`, minimal `Poc.Mod` with `-dump-tokens`) are complete.
Phase 2 (`SyntaxTree.Mod`, `SemanticActions.Mod`, `Parser.Mod`, `Poc.Mod`
`-check-syntax`) is also complete: the parser covers all of Appendix B and
successfully parses its own Phase 1/2 source. Phase 3 (`Types.Mod`,
`SymbolTable.Mod`, `ConstantEvaluator.Mod`, `Poc.Mod` `-check`) is also
complete: CONST and TYPE declarations are resolved against a real scope,
with full constant folding over the basic types (§6.1) and the numeric
inclusion hierarchy; VAR (§7) and PROCEDURE (§10) declarations are left
for Phase 5/6 per `PLAN.md`'s phase-to-section map. `HUGEINT` (see
"Language extensions beyond Oberon2.pdf" above) was added on top of this
afterward, requiring `tools/bootstrap/stage0` to switch to voc's `-OC`
build flag for adequate host-integer storage. Phase 4 (`Types.Mod`'s
array/record/procedure forms, new `MemoryLayout.Mod`, `Poc.Mod`
`-dump-layout`) is also complete: composite types resolve with real
size/alignment/field-offset computation at both a 32-bit and a 64-bit
target word size. Getting record fields to interact correctly with
Phase 3's forward-POINTER-declaration machinery required extending it
beyond what Phase 3 alone had exercised: named POINTER and RECORD
declarations now register their own Type identity before resolving
what's inside them, so the classic self-/mutually-referential linked-
structure idiom (a record field pointing back to its own enclosing
record, or to another record only reachable through a pointer) resolves
correctly instead of falsely tripping the cyclic-declaration guard - see
`src/front/SemanticActions.Mod`'s `ResolveType` header comment. Array and
procedure types don't get this same early registration (self-reference
through either still hits the plain cyclic guard) - a narrower,
deliberately unaddressed limitation. Phase 5 (`SemanticActions.Mod`'s
`CheckExpr`/`CheckStatement` families, `Types.Mod`'s
`AssignmentCompatible*`/`IsInteger*`/`FindField*`/`NilType*`) is also
complete: VAR declarations (§7), general (not-necessarily-constant)
expression/designator type-checking (§8, including a terminal-only
`v(T)`/`IS` type guard - see below), and every statement form except
WITH (§9 - WITH is deferred to Phase 6 alongside type-bound procedure
dispatch, which it shares machinery with) are all checked by `poc
-check`. Two scope boundaries are deliberately narrower than the full
report, both documented in `SemanticActions.Mod`'s own Phase 5 header
comment: a type guard/`IS` only works as a designator-expression's
*outermost* operation (`v(T)`), not with a selector chained after it
(`v(T).field`) - `Parser.Mod`'s `ParseDesignator` loop stops at `"("`
entirely and never resumes selector parsing afterward, so the mid-chain
form needs a grammar change there, deferred alongside Phase 6's own
guard/dispatch machinery; and a call through a `Types.ProcedureType`
value checks each argument expression but does not yet match the
argument list against the formal parameters (Appendix A's "matching
formal parameter lists" is `PLAN.md`'s own Phase 6 line item, and there
is no way yet to declare a real `PROCEDURE` to test the happy path
against). Writing Phase 5's `CheckExtensionApplicable` surfaced a real,
pre-existing gap in `Parser.Mod` itself while it was being smoke-tested
against poc's own source (`test/conformance/parser-self-check`): a type
guard/cast immediately followed by a selector in the *same* expression
(`x(T).field`) cannot be parsed at all today, for exactly the reason
above. Several already-committed Phase 3/4 procedures had unknowingly
relied on this exact pattern (`Types.Mod`'s `IsNumeric`/`Rank`/`Extends*`/
`ArrayCompatible*`, `MemoryLayout.Mod`'s `DescriptorSize`) - undetected
because none of those files are in `parser-self-check`'s own file list.
All were rewritten to bind the guarded value to a local variable first,
never chaining a selector directly onto a guard/cast; `parser-self-check`
itself was not widened to cover `Types.Mod`/`SymbolTable.Mod`/
`ConstantEvaluator.Mod`/`MemoryLayout.Mod`, since that is an unrelated
test-harness completeness gap, not Phase 5's own scope. See
`src/front/README.md` for the module list.

Phase 6 (`SemanticActions.Mod`'s `ResolveProcDecls`/`CheckArguments`/
`CheckWithStatement` families, a new `PredeclaredProcedures.Mod`,
`Types.Mod`'s `EqualTypes*`/`Method*`/`PredeclaredProcedureType*`) is
also complete: procedure declarations and calls with real Appendix A
parameter-list checking (§10, §10.1 - `Types.ArrayCompatible*`/
`ProcedureTypesMatch*`'s first real callers), type-bound procedures
(receivers, override checking, `r.P^` base-dispatch - §10.2), `WITH`
(§9.11, reusing Phase 5's guard-applicability pair outright), the full
§10.3 predeclared-procedure vocabulary (20 names, confirmed against the
report's own table, which has no `ASSERT`), and the grammar/resolution
side of the already-decided external-procedure-declaration syntax (see
"External procedures" above). `poc -check` now type-checks almost any
single-module Oberon-2 program, `PLAN.md`'s own Phase 5 milestone
finally reached in full. Implementing Appendix A's "matching formal
parameter lists" surfaced a genuine, previously-undetected gap: the
report's own "equal types" (used by that definition) is broader than
`Types.SameType*` (it also covers two independently-written open-array
formal types, which are never the *same* type by pointer identity, since
Phase 4 never interns `ArrayType`s) - `Types.EqualTypes*` closes this and
`ParamListsMatch` now uses it. A second gap of the same shape: Appendix
A's "array compatible" rule 3 (`ARRAY OF CHAR` matching a string
constant) requires the formal to be a *value* parameter specifically
(`AGENTS.md`'s own language-spec notes already flagged this), which
`Types.ArrayCompatible*` alone cannot know since it is a pure type-level
predicate with no notion of parameter mode - handled instead where
`CheckArguments` already knows a parameter's mode.
`PredeclaredProcedures.Mod` cannot import `SemanticActions.Mod`
(circular - `SemanticActions.Mod` is the one dispatching into it), so its
`CheckCall*` takes `CheckExpr`/`CheckDesignator` as procedure-typed
parameters instead - the
standard way to break a mutual-dependency cycle between two single-pass-
compiled modules; see that module's own header comment. Two explicit,
narrower scope boundaries, matching how Phase 4/5 recorded their own: a
function procedure's "must contain a return statement" check is shallow
(rejects only a totally empty body, not a full return-reachability
analysis), and `r.P^` base-dispatch is a narrow special case grafted onto
`CheckDesignator`'s `DereferenceSelector` branch (triggered only
immediately after a selector that resolved to a type-bound procedure),
not a generalization of ordinary pointer dereference. `poc -check-syntax`
against the new/changed front-end files themselves (`Types.Mod`,
`SymbolTable.Mod`, the new `PredeclaredProcedures.Mod`,
`SemanticActions.Mod`, `Parser.Mod`) caught one more real instance of the
guard-then-selector `Parser.Mod` limitation above, freshly introduced in
`PredeclaredProcedures.Mod`'s own `NEW` open-array-dimension check - fixed
the same way, by binding the guarded value to a local variable first.
`parser-self-check`'s own file list remains unwidened (still the same
unrelated, pre-existing test-harness gap noted under Phase 5).
