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
  `/usr/local/sw/src/lang/Oberon/vishap/compiler`
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
  `MemoryLayout.Mod` (Phase 4) separately models this same `-O2`/`-OC`
  axis for the *target* language poc itself compiles — orthogonal to this
  voc build flag, which only affects how poc's own source is compiled by
  voc. See `PLAN.md`'s "Open design questions" for that resolution;
  poc has no `-O2`/`-OC` CLI flag of its own yet, since there is no
  codegen for one to govern until Phase 8.
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

## Toolchain: LLVM (clang/llc)

Used by `poc`'s Phase 8+ LLVM backend (`PLAN.md`) — `LLVMToolchainDriver.Mod`
shells out to these rather than linking against LLVM's own C++ API.

- Installed via system packages (Fedora), both on `PATH`: `/usr/bin/clang`,
  `/usr/bin/llc`.
- Version confirmed 2026-09-18: `clang version 22.1.8 (Fedora
  22.1.8-4.fc44)`, matching `llc`'s `LLVM version 22.1.8`. Host target
  triple: `x86_64-redhat-linux-gnu`; host default data layout:
  `e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128`
  (from `clang -S -emit-llvm` on an empty `int main(){return 0;}`).
- **Build invocation, decided (`PLAN.md` Phase 8 step 1): single-step
  `clang`.** `clang <file>.ll -o <exe>` accepts textual LLVM IR directly and
  handles assembling+linking itself (confirmed with a hand-written
  `write(2)`-based "hello world" `.ll`, compiled and run successfully). A
  `.ll` file emitted by `LLVMCodeGenerator.Mod` must set its own `target
  datalayout`/`target triple` explicitly (matching the values above for the
  host, or the `-target` flag's chosen triple) — omitting them makes clang
  silently substitute the host triple with a `-Woverride-module` warning,
  which would mask a real target mismatch on cross-compiles.
- `llc` is **not** part of the normal build path — reserved as an optional
  `-dump-asm`-style debug aid for reading generated assembly in golden-file
  tests. Usage: `llc <file>.ll -o <file>.s` (its default output filetype is
  already textual assembly; unlike `clang`, it has no `-S` flag — passing
  one is a hard CLI error, `Unknown command line argument '-S'`).

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

- **`LONGREAL` literal rejected with "Value out of range"**: a `LONGREAL`
  literal whose value is integral and at least 2^31 fails to compile —
  `2147483648.0D0`, `1.0D10`, `4.5D15` all fail; `2147483647.0D0`,
  `1.0D38`, `1.0D300` and any non-integral value compile. Workaround:
  build the number arithmetically (see `LLVMCodeGenerator.DoubleBitsText`'s
  `twoTo52` loop).
- **`LONG(SHORT(x))` folded away**: voc simplifies that chain to `x`,
  skipping the narrowing to single precision it exists for. Assign
  through a `REAL` variable instead (see `LLVMCodeGenerator.RealConstant`).
- **Lossy real constants in generated C**: voc prints each `REAL`
  constant with 8 significant digits and each `LONGREAL` one with 15
  (`1.0000000e-001`, `1.00000001490116e-001`), so a constant that needs
  more digits to round-trip reads back as a different value in the C
  compiler. Only matters when cross-checking poc's output against voc's:
  three of `test/conformance/llvm-reals`'s checks fail under voc for
  this reason and pass under poc.

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
arithmetic folding). `VAR`/parameter syntax (Phase 5/6) can declare a
`HUGEINT`-typed value directly now — today it's also reachable as a
`TYPE` alias target (see `test/conformance/semantic-hugeint-type`).
Numeral literal typing (2026-09-17) now picks the minimal type per
`Oberon2.pdf` §5 — `ConstantEvaluator.IntegerLiteralType` (shared by
`EvaluateLiteral`'s `CONST` folding and `SemanticActions.CheckLiteralExpr`'s
general expression typing) selects the narrowest of `SHORTINT`/`INTEGER`/
`LONGINT`/`HUGEINT` a decimal/hex numeral's value fits, using voc's `-O2`
default byte widths (poc has no `-O2`/`-OC` CLI flag of its own yet — see
"`-OC`-equivalent elementary-type-size model" below), and reports "integer
literal too large for HUGEINT" for a numeral past even `HUGEINT`'s own
max instead of silently wrapping. Verified against real voc, including
its own boundary rejections and its "number too large" overflow
diagnostic. See `test/conformance/semantic-integer-literal-minimal-type`,
`semantic-reject-integer-literal-too-wide`,
`semantic-reject-integer-literal-overflow`.

**Appendix A / Appendix C survey for `HUGEINT` (2026-09-16,
`000-todo.org`)**: confirmed by direct inspection, not just design intent
— `Types.Mod`'s Appendix A predicates (`IsInteger*`/`IsNumeric*`/
`Includes*`/`WiderOf*`/`AssignmentCompatible*`) and `SemanticActions.Mod`'s
expression-compatible operator table (`CheckBinaryExpr`) are all rank-based,
dispatching on `BasicTypeDesc.rank` rather than enumerating specific types.
Since `hugeIntRank` was already inserted between `longIntRank` and
`realRank` when `HUGEINT` was first added, every Appendix A rule
(`+ - *`, `/`, `DIV`/`MOD`, `IN`, the six relations, assignment
compatibility, "smallest numeric/integer type including both operands")
already treats `HUGEINT` correctly with zero additional code — the only
textual changes Appendix A's own definitions need are the two already
documented above: "Integer types" gains `HUGEINT`, and the type-inclusion
hierarchy gains `HUGEINT` between `LONGINT` and `REAL`. No further Phase 5/6
work item exists here.
Appendix C (the `SYSTEM` module): a subset was pulled forward into Phase 9
step 4 (2026-09-19) - see "SYSTEM subset (partly implemented)" below. The
rest is scheduled for `PLAN.md` Phase 10 step 7 (grouped with the runtime-library
phase rather than the VAX/VMS one, since `SYSTEM` needs a real LLVM
lowering just as much as a VAX one, and has no dependency on the VAX
backend existing). When it is, two adjustments beyond the report's own
text follow from decisions already made elsewhere in this file: `ADR`/
`GET`/`PUT`/`MOVE`'s address arguments use `SYSTEM.ADDRESS`, not `LONGINT`
(see "`SYSTEM.ADDRESS` type" above — an address-width concern, independent
of `HUGEINT`), and `LSH`/`ROT`'s "`x`: integer, CHAR, BYTE" argument
category should explicitly include `HUGEINT` alongside `SHORTINT`/
`INTEGER`/`LONGINT`, since it is a genuine additional integer type by the
same Appendix A definition above. Both are documentation-only conclusions
today; there is no `SYSTEM.Mod` yet for either to apply to.

### SYSTEM subset (partly implemented)

`IMPORT SYSTEM` binds a pseudo-module (no source, no `.sym`;
`SymbolTable.SystemScope`) offering `ADDRESS`, `ADR`, `GET`, `PUT`, `VAL`
and `MOVE`, pulled forward from Phase 10 step 7 because the garbage
collector (`rtl/llvm/GarbageCollectedHeap.Mod`, written as ordinary Oberon-2
over raw addresses) needs them. `SYSTEM.ADDRESS` is deliberately **not**
voc's `LONGINT` alias: it is its own integer type, as wide as a pointer on
the target, ranked between `LONGINT` and `HUGEINT` in the numeric hierarchy
(`LONGINT ⊆ ADDRESS ⊆ HUGEINT` - a `LONGINT` can be assigned to an address,
not the reverse). `GET`/`PUT` access memory with no alignment assumption;
`PUT(a, x)` stores `x` at `x`'s own type, so a bare numeral is stored at
its minimal integer type's width (`PUT(a, 5)` writes a `SHORTINT`-sized
value under `-O2`). `VAL(T, x)` between scalars of different widths
sign-extends or truncates - the report leaves it undefined and voc warns.
`BYTE`, `PTR`, `BIT`, `LSH`, `ROT`, `SYSTEM.NEW` and the fixed-width types
are still Phase 10 step 7's.

### Pointers, `NEW` and the runtime (implemented, Phase 9 step 5)

Points where `Oberon2.pdf` is silent and poc made a choice (`PLAN.md` step 5
has the full account; all probed against real voc 2026-09-19):

- **NIL handling**: every dereference (`p^`, and the implied one in `p.f`
  and `p[i]`) is NIL-checked and traps ("NIL pointer dereference", exit
  status 4), like voc's default `-p`. `NIL IS T` is **FALSE**, a type guard
  `NIL(T)` **passes**, and a NIL `WITH` variable matches no branch - where
  voc traps "NIL access" on all three. Anything voc accepts therefore means
  the same here. A failed guard exits 5, a `WITH` with no matching branch
  and no `ELSE` exits 6, a `NEW` the heap cannot satisfy exits 7 (the
  report says nothing about running out of memory).
- **`&` and `OR` short-circuit** (Appendix A requires it; poc kept them
  eager through Phase 8 while nothing could observe the difference).
- **`NEW` needs the runtime on the import path**: no module imports
  `GarbageCollectedHeap`/`ModuleTable` for it - `poc` adds both to the
  program itself whenever any module calls `NEW`, finding them like any
  imported module (`POC_IMPORT_PATH=<repo>/rtl/llvm` or `-import-path`).
  There is no built-in default directory; a missing runtime is an error
  message naming the module.
- Pointer variables start NIL, locals included (a local holding a pointer
  is zeroed on entry). Heap blocks come back zero-filled.
- Not yet: `NEW(p, n)` and pointers to open arrays (step 7), type-bound
  calls and guards on `VAR` record parameters (step 6), procedure values.

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
  Phase 8's LLVM/C-interop case, `"VMS"` for Phase 11's VMS Calling
  Standard case — both accepted now, even though nothing consumes
  `"VMS"` until Phase 11). An optional second string overrides the
  external linkage name, since Peaseblossom's own naming convention (see
  "Naming feedback" — descriptive, often-long identifiers) routinely
  won't match a terse external symbol like `malloc` or `printf`:
  `PROCEDURE ["C", "malloc"] AllocateBytes*(size:
  LONGINT): SYSTEM.ADDRESS;`. Without the second string, the external
  symbol is the procedure's own Oberon identifier verbatim
  (`SymbolTable.ObjectDesc.externalName`). This interacts with the VAX
  backend's 31-character name-mangling requirement (Phase 11, below): an
  external procedure's linkage name is emitted **verbatim, never
  mangled** — it has to match the real external symbol, unlike poc's own
  internally-generated names. Both backends' actual lowering is still
  Phase 8/11 work; Phase 6 only records the linkage info
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
expression/designator type-checking (§8, including `v(T)`/`IS` type
guards - see below), and every statement form except WITH (§9 - WITH is
deferred to Phase 6 alongside type-bound procedure dispatch, which it
shares machinery with) are all checked by `poc -check`. One scope
boundary is deliberately narrower than the full report, documented in
`SemanticActions.Mod`'s own Phase 5 header comment: a call through a
`Types.ProcedureType` value checks each argument expression but does not
yet match the argument list against the formal parameters (Appendix A's
"matching formal parameter lists" is `PLAN.md`'s own Phase 6 line item, and there
is no way yet to declare a real `PROCEDURE` to test the happy path
against). Writing Phase 5's `CheckExtensionApplicable` surfaced a real,
pre-existing gap in `Parser.Mod` itself while it was being smoke-tested
against poc's own source (`test/conformance/parser-self-check`): a type
guard/cast immediately followed by a selector in the *same* expression
(`x(T).field`) couldn't be parsed at all, for exactly the reason above.
Several already-committed Phase 3/4 procedures had unknowingly relied on
this exact pattern (`Types.Mod`'s `IsNumeric`/`Rank`/`Extends*`/
`ArrayCompatible*`, `MemoryLayout.Mod`'s `DescriptorSize`) - undetected
because none of those files are in `parser-self-check`'s own file list.
All were rewritten at the time to bind the guarded value to a local
variable first, never chaining a selector directly onto a guard/cast.
Resolved 2026-09-17 (`Parser.Mod`'s `TryParseGuardSelector`,
`SemanticActions.Mod`'s `CheckDesignator` `GuardSelector` case - see
`PLAN.md`'s "Type guards in designators") - `x(T).field` parses and
type-checks correctly now, but those Phase 3/4 workarounds were left as
they were rather than revisited, since simplifying already-tested
Appendix A predicates for a purely cosmetic win wasn't worth the risk;
`parser-self-check` itself was not widened to cover `Types.Mod`/
`SymbolTable.Mod`/`ConstantEvaluator.Mod`/`MemoryLayout.Mod` either,
since that remains an unrelated test-harness completeness gap. See
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

Phase 7 (`ModuleInterface.Mod` (new), `SemanticActions.Mod`'s
`CheckModuleBody`/`ResolveImport`/`FindQualified`, a new `poc
-emit-interface` mode) is also complete: qualified names (`Module.Ident`)
now resolve end to end, backed by a textual, on-disk `<ModuleName>.sym`
interface file. Per a decision confirmed with the user while planning this
phase, a `.sym` file is literally valid Peaseblossom module source
(`MODULE Name; ... END Name.`, exported declarations plus - since Phase 9
step 4a - the unexported ones an importer's layout depends on, see "Hidden
members in `.sym` files" below, every
procedure/type-bound procedure written as a permanently body-less
`PROCEDURE^ ...;` forward declaration) rather than a separate
Appendix-D4-style grammar - `SemanticActions.CheckModule` already
tolerated (confirmed: no such check existed) a forward declaration never
being completed within one compilation, which is exactly what makes an
all-forward-declared `.sym` checkable by the same `CheckModuleBody` used
for real programs. `ModuleInterface.Mod` owns only text I/O in both
directions (`Write*`/`ReadSource*`) and deliberately cannot import
`Parser.Mod` (which already imports `SemanticActions.Mod`, which now needs
to call into `ModuleInterface.Mod` - importing `Parser.Mod` too would be a
real cycle); `SemanticActions.CheckModuleBody` instead takes a
`ParseModuleProc` callback, concretely supplied by `Poc.Mod` (the only
module already importing both `Parser.Mod` and `SemanticActions.Mod`
without creating one) - the same procedure-typed-parameter shape
`PredeclaredProcedures.Mod` already established, one layer up (a
module-level import cycle instead of an intra-module one). A new
`SymbolTable.moduleClass`/`ObjectDesc.moduleScope` binds an imported
module's name (or its alias) into the same top-level scope ordinary
declarations go into, exactly mirroring Oberon2.pdf's own grammar
(`ImportList` is part of the module's declaration scope) - a name clash
between an import and a declaration is caught by `Insert`'s existing
duplicate check for free. Genuine cross-module recursion (resolving one
`.sym`'s own imports) is real, but reading is always from an
already-finalized file on disk, never a re-entry into the module currently
being checked - still, two separately-written `.sym` files can end up
mutually referencing each other after enough separate compiles (documented
in `SemanticActions.Mod`'s own `ImportChain` header comment with a concrete
repro), so `CheckModuleBody` threads a small "currently resolving" name
chain and rejects a real cycle explicitly, mirroring
`SymbolTable.ObjectDesc.resolving`'s existing self-reference-guard idiom
one level up.

`FindQualified` (`SemanticActions.Mod`) is the one shared qualified-name
lookup every qualifier-bearing site now routes through, replacing five
separate "qualified names are not yet supported" rejections found while
implementing this phase (`ResolveQualidentType`, `CheckDesignator`,
`LookupBareTypeName`, and both of `CheckWithGuard`'s variable/type
qualifiers) - more sites than anticipated at planning time.
`ConstantEvaluator.Mod` and `PredeclaredProcedures.Mod` each had their own,
separate qualifier rejection too (constant expressions; `MAX(T)`/`MIN(T)`/
`SIZE(T)`'s bare-type-name argument) - both cannot import
`SemanticActions.Mod` (dependency order/circularity, the same reasons
already documented in each module's own header comment), so each got its
own small, deliberately duplicated version of the same lookup rather than
an injected dependency, continuing this codebase's own established
precedent for that tradeoff.

Testing this phase against the report's own `Trees` example (Ch. 11)
surfaced a real, previously-unobservable correctness bug, now fixed: `-`
read-only export (Oberon2.pdf §4: "read-only in importing modules")
was being enforced unconditionally, including within the very module that
declared the field - which made `NewTree`'s own `t.name := ...` illegal,
even though nothing outside the module could previously reference another
module's field at all (so the distinction was moot before this phase).
Fixed two ways: a bare `VAR`'s own read-only mark is now gated on the
designator's own qualifier (`d.qualifier[0] # 0X`- an unqualified
reference can only ever resolve within the current module's own scope
chain by construction, so this is a sufficient and exact signal); a record
field reached via `.` is gated on whether the field's *owning* record was
declared by the current module (`IsLocalType` when written, since replaced
by an exact `rec.moduleName` test - see "Hidden members in `.sym` files"
below) - needed separately because
a field can be reached *indirectly* through a local variable whose own
type was imported (`VAR t: OtherModule.T; t.f := ...`), which a
qualifier-only check on the outer designator would miss entirely. The
existing `semantic-reject-assign-readonly-field` fixture (single-module,
no imports) was testing exactly the behavior this fix removes; renamed to
`semantic-readonly-field-same-module` and inverted to a positive
"semantic OK" case, with `semantic-reject-readonly-import-field` (new,
genuinely cross-module) taking over coverage of the real restriction.

`Types.ParamDesc` gained a `name*` field and `Types.MethodDesc` gained a
`receiverTypeName*` field (both already available at their existing call
sites in `SemanticActions.Mod`) purely so `ModuleInterface.Mod` can print
real parameter names and the receiver's literal declared type spelling
(which may be a `POINTER TO` alias distinct from the record's own name,
the report's own `Tree`/`Node` idiom) instead of placeholders. Building
`SymbolTable.Mod`'s new `moduleScope` field surfaced a real Oberon2.pdf §4
rule-3 subtlety while writing poc's own source: the forward-reference
exception ("`T = POINTER TO T1`, `T1` declared later in the same block")
covers only that exact top-level shape (confirmed against real `voc`) -
an arbitrary field naming an inline, anonymous "`POINTER TO
NotYetDeclaredRecord`" is rejected as an undeclared identifier, even
though `Object`/`Scope` were already mutually recursive by construction.
Fixed by declaring `Scope* = POINTER TO ScopeDesc;` on its own, ahead of
`Object*`/`ObjectDesc*`, so `ObjectDesc` can reference the already-known
name `Scope` directly. Separately, `Files.WriteString` (confirmed against
real `voc`) writes its argument's terminating `0X` into the file, not just
the characters before it - harmless for Oakwood-library callers that
always read text back through `Files.ReadString`/`ReadLine`, but wrong for
a plain-text `.sym` meant to be read back by `Lexer.Mod`, which would see
a stray NUL between every single piece written; `ModuleInterface.Mod`'s
own `WriteStr` (via `Files.Write`, confirmed to accept a bare `CHAR`
directly) works around this.

Several explicit, narrower scope boundaries, matching how every prior
phase recorded its own: the import search path was cwd-only at first
release (`.sym` files looked up as `Files.Old(moduleName + ".sym")`
relative to the working directory only) - since extended, see "IMPORT
search path" below, as is `.sym` output's own cwd-only default - see
"Output directory" below; `ModuleInterface.Mod` could not, at first,
export a `REAL`/`LONGREAL`-valued `CONST` at all (explicit diagnostic,
not lossy text) - also since resolved, see "REAL/LONGREAL CONST export"
below; a written `.sym`'s `IMPORT` line unconditionally re-exports every
import the module itself declared, not just the ones some exported
signature actually references (avoids a separate used/unused pass over
every printed type - and, since Phase 9 step 4a, load-bearing rather than
merely harmless: a hidden member's type may come from a third module);
`IsLocalType` treated a local `TYPE` alias of an imported record
(`TYPE Local = OtherModule.T`) as local too - a real but rare
read-only-enforcement loophole, closed by Phase 9 step 4a's exact
`rec.moduleName` test; and
a qualified `WITH` variable (`WITH M.v: T DO`) - resolved 2026-09-17, not
by narrowing it but by rejecting it outright, matching real voc: see
`PLAN.md`'s "Type guards in designators" entry, gap (2), and
`CheckWithGuard`'s own header comment in `SemanticActions.Mod`. New conformance coverage:
`module-interface-write` (golden-diffs a `.sym` file itself, not just
stdout), `module-cross-import` (a `Trees`-derived library plus a client
that only ever sees its `.sym`), and four negative fixtures
(`semantic-reject-unknown-module`, `semantic-reject-self-import`,
`semantic-reject-not-exported`, `semantic-reject-readonly-import-field`) -
the cross-module export-visibility tests deferred since Phase 3 land here,
as `PLAN.md` anticipated. `poc`'s own front-end source does not yet use
`IMPORT`-based multi-file checking itself (each module is still built as a
single voc compilation unit via `tools/bootstrap/stage0`), so the
Phase-5-style self-check milestone for this phase is `tools/bootstrap/stage0`
itself succeeding end to end with `ModuleInterface.Mod` compiled in
(confirmed) rather than a new `-check`/`-check-syntax` invocation.

**IMPORT search path** (`PLAN.md`'s "Open design questions", closing the
`000-todo.org` item of the same name): `ModuleInterface.Mod` now searches
the current directory first (unchanged, still required for every existing
multi-module fixture), then a process-lifetime list of extra directories
it owns (`searchPathHead`/`Tail`, `AddSearchPathDir*`/`AddSearchPathList*`/
`ClearSearchPath*`/`FirstSearchPathEntry*`). `Poc.Mod` is the only caller:
it seeds the list from the `POC_IMPORT_PATH` environment variable (colon-
separated, read once via `Platform.GetEnv` at startup) and/or repeated
`-import-path <dir>` flags, both of which may precede any existing command
on the same invocation; `-clear-import-path` empties the list regardless
of where its entries came from; `-print-import-path` prints it and exits.
Since the list only lives for one process's `Run`, list-management flags
only matter combined with a later flag in the *same* command line - two
separate `poc` invocations share nothing. `Platform.GetEnv` is a deliberate,
narrow exception to `Poc.Mod`'s own header-comment rule about avoiding
Vishap-specific extensions: that rule is about *language syntax*
(`HUGEINT`, read-only value params, etc.), not which library modules the
driver may import, and `Modules.ArgCount`/`GetArg` already read the host
environment the same way; `ModuleInterface.Mod` itself never reads the
`POC_IMPORT_PATH` environment variable directly (only `Poc.Mod` does),
though it does import `Platform` itself for an unrelated reason - see
"Output directory" below. New conformance coverage:
`module-import-path` (a library in a `lib` subdirectory, only resolvable
via `-import-path lib`), `semantic-reject-import-not-on-path` (the same
library, without the flag, confirming cwd-only lookup still correctly
fails), and `import-path-print` (golden-diffs `-print-import-path`'s
output across env-only, CLI-only, env+CLI, and clear-then-add
combinations in one invocation each).

**Output directory** (closes `000-todo.org`'s "output directory for build
artifacts" item): `-output-dir <dir>` may precede `-emit-interface` (the
only command that writes a file today - a future Phase 8 codegen command
would take the same parameter) to write `<ModuleName>.sym` there instead
of the current directory; unlike `-import-path` it has no environment-
variable seed (not asked for) and no list (a later `-output-dir` simply
overrides an earlier one). Implementing this surfaced a real, sharp voc
behavioral difference: `Files.Old` (used throughout `ReadSource*`/`Open`)
returns `NIL` cleanly on a missing file or directory, confirmed and relied
on since Phase 7, but `Files.New` does **not** - confirmed against real
voc that writing into a nonexistent directory instead runs the runtime's
own uncatchable `Halt(99)`, which would have taken the whole `poc`
process down. `ModuleInterface.Mod`'s `Write*` now validates the
directory first via `Platform.Chdir` (which does return a plain,
non-crashing error code - confirmed `res=2`/`ENOENT` on a bad path),
saving and restoring the real working directory via `Platform.CWD-`
around the write, and only calling `Files.New` (with a bare file name,
now relative to whatever the current directory is) once `Chdir` has
already succeeded; a `Chdir` failure is reported as an ordinary write
failure with no crash. This is `ModuleInterface.Mod`'s own first `Platform`
import (previously only `Poc.Mod` needed it, for `GetEnv`) - documented on
`Write*`'s own header comment as the same kind of narrow, deliberate
exception to the "no Vishap extensions" rule as `Platform.GetEnv` already
was, and still nothing to do with reading environment variables. New
conformance coverage: `output-dir-write` (golden-diffs both the stdout
message and the written file's contents from a `lib` subdirectory built
fresh by `test.sh`, matching how `test/testenv.sh`'s existing artifact
cleanup already treats generated `.sym` files) and `output-dir-missing`
(confirms a nonexistent `-output-dir` fails cleanly rather than crashing
the process).

**REAL/LONGREAL `CONST` export** (closes `000-todo.org`'s "round-trip-
safe float-to-text formatter" item): `ModuleInterface.Mod` can now export
`REAL`/`LONGREAL`-valued `CONST`s, but via two tiers rather than one
general algorithm - see `LiteralRealLexeme`'s and `FormatRealMagnitude`'s
own header comments for the full detail each summarizes here. (1) The
common case, a `CONST` declared as a bare literal (optionally
unary-`+`/`-`'d) - `Pi* = 3.14159265358979;`, `Neg* = -123.456;` - just
echoes the token's own lexeme text verbatim, via the `SyntaxTree.ExprNode`
now threaded down from `PrintConsts` alongside the already-folded
`Types.Value`; re-lexing/re-parsing identical characters through the
identical `ConstantEvaluator.ParseReal` is trivially exact, no
value-to-text algorithm needed at all. (2) Anything else (a computed
expression like `1.0/3.0`, a reference to another constant) still needs
one, via `FormatReal`/`FormatRealMagnitude` - search increasing precision
(and a small window of neighboring digit values at each one, not just the
nearest rounding) until a candidate verifies exactly against
`ConstantEvaluator.ParseReal` itself, never assumed correct from a
"N significant digits always round-trips" argument. That verification
step surfaced two real, previously-invisible bugs in `ParseReal`, both
now fixed (present since Phase 3, invisible until something finally
printed a folded value at full precision): every numeral literal *inside
ParseReal's own source* (`0.1`, `10.0`, `0.0`) was untyped `REAL`, not
`LONGREAL`, per `Oberon2.pdf`'s own real-literal typing rule, so voc
evaluated each at single-precision before ever widening it - confirmed
with a standalone repro (`"1.5"` parsed back as `1.5000000074505800`, an
exact float32-epsilon error) and fixed by `D0`-suffixing every one of
those literals; and, separately, `ParseReal`'s fixed-point path (plain
digit accumulation) and its scientific-notation path (the same, plus a
repeated-`*10.0D0` exponent-scaling loop) can land on different `LONGREAL`
bit patterns for "the same" number, since floating-point arithmetic isn't
associative - the reason tier (1) exists at all, rather than routing
every `CONST` through tier (2)'s reformat-and-verify approach. New
conformance coverage: `module-interface-real-write` (golden-diffs a `.sym`
with a representative literal/negative-literal/computed-expression mix,
including an unexported one that must not appear) and
`module-interface-real-roundtrip` (the strongest test available without a
backend to actually run anything: `-emit-interface` twice in a row, the
second time treating the first run's own `.sym` as input source, must
produce byte-identical output - direct evidence that
`ParseReal(FormatReal(v)) = v` holds for real, not just that `FormatReal`
believed it did).

**Hidden members in `.sym` files** (Phase 9 step 4a, 2026-09-19 - `PLAN.md`
has the full design and the voc comparison): a `.sym` now carries every
field and type-bound procedure of every record it prints, exported or not
(unexported ones carry no export mark), plus every unexported `TYPE` those
members or any exported signature reach, transitively, printed as ordinary
unexported declarations - so a module extending an imported record can
reproduce its base's layout and `ProcTab` slot numbering itself, at its own
word size and size model. (voc instead stores computed sizes, offsets and
method numbers in a binary `.sym`, which is why it ships one symbol tree
per size model; poc keeps one target-independent, valid-source `.sym`.)
`ModuleInterface.Write*` finds the needed unexported types by running its
whole printing pass repeatedly with output suppressed until nothing new is
found, then once for real, so marking and printing share every lookup rule.
The invariant "`moduleScope` holds only exported members" no longer holds,
so the reading side enforces export explicitly: `FindQualified` rejects an
unexported name ("identifier is not exported by its module"), and field /
type-bound-procedure selection rejects an unexported member unless the
record that *declared* it (`Types.FieldOwner`/`MethodOwner`, not the record
the access went through) belongs to the current module (`IsLocalRecord`:
every `RecordType` is stamped with its declaring module at creation). An
unexported CONST/VAR/PROCEDURE is still simply absent from a `.sym`, so
naming one still says "undeclared identifier". Verified against real voc
(2026-09-19): hidden base members take no part in an importer's *name*
rules - an extension may declare a field of the same name as a hidden base
field (two distinct fields) and a type-bound procedure of the same name as
a hidden base one with any signature (a new procedure in its own slot, not
an override) - so `Types.FindOverridable` (exported, or declared in the
same module) decides what an extension can override, shared by the checker
and `LLVMTypes`' slot numbering. Whole-program commands (`-emit-llvm-ir`,
`-build`) now regenerate every transitive import's `.sym` from real source
(post-order, into the output directory, which `ReadSource*` searches first)
before checking the top module, since a stale `.sym` would otherwise give an
importer a different record layout than the imported module's own code.
Three previously latent bugs surfaced and were fixed along the way: two
exported names sharing one type printed as the cyclic `A* = B; B* = A;`;
`ResolveProcDecls` treated an override of an *imported* procedure as
completing that procedure's forward declaration (mutating the base's
method and never recording the override); and a function returning a
pointer emitted the invalid placeholder `ret ptr 0`. Not done: the optional
`-show-interface` (exported-view-only) mode.
