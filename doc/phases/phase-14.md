# Phase 14 — Record and array literals, and structured constants

Moved here from `PLAN.md` on 2026-10-04, once the phase was done, with
step 6's record written at the close-out. `PLAN.md` keeps the heading,
the goal, and a list of the steps, so a reference elsewhere to "`PLAN.md`
Phase 14 step N" means step N here. The rules are in
`doc/language-extensions.md`, "Record and array literals", and the design
and survey in `doc/record-and-array-literals.md`.


**Added 2026-10-02 (user)**, after Phase 13 and before the VAX/VMS work,
taking record and array literals out of the further extensions (now
Phase 19, where they were candidate 1, from Phase 11 A24). The later
phases moved up by one.

**Goal**: a value of a record or fixed array type written in an
expression, `Point{x := 1, y := 2}` and `Vector{1, 2, 3}`, in the LLVM
backend, with the front end's part shared by the VAX backend later.
`doc/record-and-array-literals.md` has the design: the decisions taken
with the user, the rules in detail, the survey of other dialects (Active
Oberon, Oberon+, Micron, Modula-3, ISO Modula-2, Ada, and those with
none; the first survey, 2026-09-26, is `doc/initializers-and-literals-
survey.md`), and what the implementation touches.

**Decided** (user, 2026-10-02): `T{...}`, the type always named; record
elements named only, `field := expression`; omitted elements take their
defaults (a field its initializer or zero, an array's later elements the
same, so an array of records gets its type's default records); no literal
of a record type with a field hidden or read-only where the literal is
written; and structured constants, `CONST origin* = Point{x := 0, y :=
0};` (user, 2026-10-02, reversing the first decision against them), so
`Types.Value`, the constant folder and the `.sym` format change too.
`-strict` rejects a literal. **Decided** (user, 2026-10-03, step 1): a
literal is made as a variable is, every default first, then its elements
in the order written; a constant field initializer goes into the `.sym`
file as its value; repeated elements, open array literals and a bare
`{...}` outside a literal are not in this phase. **Added** (user,
2026-10-03, after step 6): indexed array elements, `[48..57]: 1`, labels
as a `CASE`'s, positional elements continuing after the highest index,
each index at most once, a range's element evaluated once per index.

**Steps**:

1. **The rules settled** in `doc/language-extensions.md` (a section
   "Record and array literals", with its one-line summary in `AGENTS.md`),
   from the design note: what a literal's type may be, the element rules,
   nested literals and when a nested one may leave out its type name,
   strings as elements, evaluation order, where a literal may stand, and
   type extension. Decide the open questions the note lists (indexed or
   repeated array elements, a literal of an open array type, inferring a
   bare `{...}`'s type), each "not in this phase" unless the user says
   otherwise.
2. **Front end**: a literal node in `SyntaxTree`; `Parser` reads
   `designator {` as a literal and a nested bare `{...}` as a list to be
   resolved; `SemanticActions` checks the type, each element's
   compatibility, repeated and unknown fields, the length, the visibility
   rule, resolves a bare `{...}` as a set or a literal by the expected type,
   and rejects a literal where it may not stand (a `VAR` parameter,
   `-strict`). **Testing**: `semantic-` fixtures accepting literals and
   rejecting each error, with their messages.
3. **Structured constants**: a structured `Types.Value`, folded by
   `ConstantEvaluator` from a constant literal and through selectors
   (`origin.x`, `table[3]`); a `CONST` declared by a literal, used as a
   read-only operand; an exported one written to the `.sym` file as its
   literal, every element given, in a `CONST` section after `TYPE`, and
   read back through the parser. The rules are the design note's
   "Structured constants", settled in step 1. **Testing**: `semantic-`
   and `module-` fixtures: folding, selection, rejection (a non-constant
   element, a `VAR` parameter, assignment, a hidden type exported), and a
   constant exported and imported.
4. **LLVM backend**: a literal is made in a stack slot of its own, in
   the function's entry block, zeroed and initialized as a variable is
   (field initializers, Phase 11 D17), then its elements stored in order;
   a structured constant is a private constant global of each module that
   uses it, addressed like a variable (as built; the first plan, a
   constant aggregate or an `insertvalue` chain, was dropped:
   `doc/record-and-array-literals.md`). Debug information needs nothing
   new. **Testing**: `llvm-` fixtures that build and run:
   records, arrays, nested literals, omitted elements and defaults, arrays
   of records, literals as value and open-array parameters, in variable
   and field initializers, of an extension assigned to its base, with
   pointers inside (and a collection while one is live), under both size
   models; and structured constants, local and imported, passed and
   indexed with a variable (each module's private copy); voc cannot
   cross-check any of them.
5. **Documentation**: the User's Guide (an example the suite runs) and
   the Reference Guide (Phase 13 step 7) describe literals and structured
   constants.
6. **Exit gate**: `make check` on atla and the gating VMs; Stage 1 and
   Stage 2 still reach their fixed point; rackhir at the close-out.

   **Record** (closed 2026-10-04): steps 1-5 and the gate were committed
   together as 623ad98 (2026-10-03), after `make check` passed on atla,
   cymoril, artos and alerik (668 fixtures each, Stage 1 and Stage 2
   identical); the indexed array elements added after step 6 as 962c22a
   (672 on the same four). rackhir's `gmake check` passed both: 623ad98
   (668) and, for the close-out, 962c22a (672, 2026-10-04), each with
   Stage 1 and Stage 2 identical. Between them and the close-out, the four
   bugs below were fixed (526d7ba, 680 fixtures on the four gating hosts),
   one of them in this phase's own code (a string constant's text, now
   `Lexer.Text`).

   What the implementation found, beyond the design note: a procedure's
   declarations are checked a second time when the backend reopens its
   scope, with no current module, so the visibility rule for a literal is
   skipped then (`SemanticActions.CheckLiteralVisibility`); the constant
   folder compares a constant `ARRAY n OF CHAR` with a string as the
   string it holds (`ConstantEvaluator.CharArrayAsString`); a `REAL` zero
   keeps the numeral it was written as, so a structured constant's `-0.0`
   stays negative; and only an aggregate is written as `zeroinitializer`
   in a constant global, never a scalar zero. A literal's error in a
   module that also has a parser-level `-strict` error (an initializer) is
   not reported, because checking stops after the parser's errors - as it
   did before this phase.

**Testing summary**: steps 2-4 add fixtures; step 6 is the usual gate.

## Ongoing bug fixing, during Phase 14

`PLAN.md`'s "Ongoing bug fixing" section was started on 2026-10-04 for
bugs found by using poc on other programs; its fixed items move to the
record of the phase current when they were fixed, at that phase's
close-out. All four were fixed in 526d7ba, each with a fixture
(`llvm-imported-external-procedures`, `semantic-check-word-size`,
`llvm-long-strings`, `semantic-strict-compiled-imports`), after `make
check` passed on atla, cymoril, artos and alerik (680 each); rackhir runs
on it separately, as on every pushed commit.

Found porting olibfyaml (the libfyaml binding for voc) to poc as
`~/Repos/Oberon/polibfyaml`, 2026-10-03, with 0.1.0 and HEAD 962c22a
(polibfyaml's AGENTS.md, "poc 0.1.0 problems", has its workarounds):

1. `[fixed]` **An exported external procedure can't be called from another
   module.** `ModuleInterface.PrintFreeProcs` writes `PROCEDURE ["C",
   "fy_document_destroy"] DocumentDestroy*(fyd: SYSTEM.ADDRESS);` into the
   `.sym` as `PROCEDURE^ DocumentDestroy*(...)`, losing the calling
   convention and linkage name, so the importer calls
   `@FyThin.DocumentDestroy`, which nothing defines: "use of undefined
   value". AGENTS.md's "External procedures" shows an exported one as the
   example. Fix: write the external attribute, with its linkage name
   always explicit, so the importer's checker resolves it as it would a
   local external declaration; the backend already calls an imported
   external by its linkage name (`DeclareModuleSymbols`).
2. `[fixed]` **`poc -check` uses the wrong word size.** Under `-OC` on x86-64 it
   rejects `a := l` (`a: SYSTEM.ADDRESS; l: LONGINT`), "assignment is not
   type-compatible", which a build of the same module accepts
   (`semantic-address-width` has the table): `-check` does not set the
   target's word size before checking.
3. `[fixed]` **A string literal holds at most 255 characters**
   (`Lexer.maxLexemeLength`; voc's `OPS.MaxStrLen` is 1024), so
   olibfyaml's `TestScalars`, a 700-character document, failed with
   "string too long, truncated". Fix (decided with the user 2026-10-04):
   no limit - a string literal's text (`Lexer.Token.text`,
   `LiteralExprNode.string`) and a string constant's value
   (`Types.Value.stringVal`) are `Lexer.Text`, a `POINTER TO ARRAY OF
   CHAR` sized to fit; identifiers keep their 255.
4. `[fixed]` **`-strict` held a library's interface to the report.** Found while
   testing 1: `poc -strict` on a module importing `Out` reported
   "HUGEINT is not in the Oberon-2 report" in poc-rtl's `Out.sym`, and so
   for any module given as its `.sym` and `.o`: `DiscoverLibraryModule`
   and `DiscoverCompiledModule` did not turn `-strict` off for the
   interface, as `DiscoverModule` does for a module's source (in 0.1.0
   too). Fix: they do, and `SemanticActions.ResolveImport` now turns it
   off before parsing an imported `.sym`, not only before checking it.

## Peaseblossom 0.2.0

Phase 14 and these four fixes were released as **Peaseblossom 0.2.0** on
2026-10-04 (decided with the user: a minor release from `main`, since it
adds a feature), as `doc/DEVELOPER.md` section 7 says: the version in
`87bbcaa`, after `make check` on atla, cymoril, artos and alerik (680
each) with `check-opt2`, `check-install` and `check-seed` on atla; the
tarball by `make distcheck` (SHA-256 `230f70ea...`, 3433514 bytes),
signed, with the signed tag `v0.2.0`, published as a GitHub release.
Each package was made from the published tarball (`makesum`), built and
checked on its system (`check.sh` on the build root or stage; portlint,
portcheck and pkglint clean; packing lists unchanged), installed as
root, checked with `check.sh` against the installed poc, and removed with
nothing left (on atla the 0.2.0 RPM stays installed, replacing 0.1.0);
the RPMs signed with `rpmsign` and attached with the other packages and
a signed `SHA256SUMS`. `mock` was not run.
