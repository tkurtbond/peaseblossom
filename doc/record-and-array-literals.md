# Record and array literals, and structured constants (proposed extension)

A value of a record or fixed array type written in an expression:

    p := Point{x := 1, y := 2};
    v := Vector{1, 2, 3};
    Draw(Line{from := Point{x := 0, y := 0}, to := p});
    CONST origin* = Point{x := 0, y := 0};

Not yet implemented: `PLAN.md`'s Phase 14 (added 2026-10-02). Phase 11's
item A24 first, then a candidate of the further extensions (now Phase 19)
from 2026-09-26, whose survey, `doc/initializers-and-literals-survey.md`,
also covers oo2c, obc and OBNC. This note holds the decisions taken with
the user (2026-10-02), the survey of other dialects they were checked
against, what the implementation would touch, and the questions still
open.

The rules as settled in Phase 14 step 1 (2026-10-03) are in
`doc/language-extensions.md`, "Record and array literals", which
controls where this note differs: a literal is made as a variable is,
every default applied before the elements are assigned; a constant field
initializer is written to the `.sym` file as its value; an exported
structured constant may have hidden fields; and the open questions below
are left out of Phase 14.

## Decisions

1. **Syntax: `T{ ... }`**, a named type followed by its elements in
   braces. The type is always written, so a literal never needs its type
   inferred from where it stands. A named record element is
   `field := expression`, as in poc's variable and field initializers
   (`doc/language-extensions.md`, "Variable initializers", "Record field
   initializers").
2. **Record elements are named, never positional.** Positional elements
   would silently change meaning when a field is added, reordered or moved
   into a base type.
3. **Elements may be omitted.** An omitted field gets its default: its
   initializer if it has one, otherwise zero, exactly as for a variable or
   `NEW` (Phase 11 D17). An array literal may have fewer elements than the
   array's length: the elements after the last one written get the same
   default, so in an array of records each omitted element is a record with
   its type's default initialization.
4. **No literal of a record type with a hidden or read-only field.** A
   record type with a field not exported, or exported read-only (`-`), to
   the module that writes the literal (its base types' fields included)
   has no literal there. Inside the module that declares it, where every
   field is visible and writable, it has one.
5. **Structured constants, in this phase too** (user, 2026-10-02; at
   first left out, an exported read-only variable doing the job): a
   literal whose elements are all constant is a constant, and may declare
   one, `CONST origin* = Point{x := 0, y := 0};`. As every Oberon constant,
   it states no type of its own: the type is the literal's. The rules
   proposed for it are under "Structured constants" below.

Like every extension, `poc -strict` rejects a literal.

## Survey of other dialects

Checked against each language's own report or specification, 2026-10-02.

| Language | Structured literals | Syntax | Notes |
|---|---|---|---|
| Oberon-2 (`Oberon2.pdf`; 1993 report) | none | - | `Factor` has only `Set` as a constructor |
| Oberon-07 (Wirth, 2013/2016 report) | none | - | same `factor` as Oberon-2 |
| Component Pascal (Oberon microsystems, 2001 report) | none | - | same `Factor` |
| Oberon-2, 2020 edition (Pirklbauer, 2023) | none | - | its list of changes has none |
| Oberon-3 (Ofront+, `Oberon-3.rst`) | none | - | differences from Component Pascal list none |
| Zonnon (report v03r01, 2005) | none | - | only set constructors |
| Active Oberon (ETH Oberon 2019 report, Friedrich and Negele, section 2.6) | arrays only | `[1, 2, 3]`, nested `[[...], [...]]` | elements must be constant; the type is inferred: a static math array of the literal's length and the smallest common element type. No record literals |
| Oberon+ (`oberon-lang/specification`, 2026) | none yet | - | its TODO list names both candidates: `[1, 2, 3]`, or "like ISO Modula like `Array1dType{ 1,2,3 }`", "which would also support record literals" |
| Micron (`micron-language/specification`, 2026; also by R. Keller, the Oberon+ author) | records, arrays, pointers, procedures | `[NamedType] '{' component {[','] component} '}'`, component `ident ':' expression`, `'[' index ']' ':' expression`, or positional | type may be omitted where it can be inferred; constant when all components are; omitted fields and elements get their default; a record or object type with a base type imported with private or read-only fields has no constructor; `@T{...}` is an anonymous local variable |
| ISO Modula-2 (ISO/IEC 10514-1; Schönhacker's summary) | records, arrays, and structured constants | `TypeName{...}`, positional, `x BY n` repeats an element | the type identifier is always required ("precludes any ambiguities with regard to the component types"); elements may be variables, not only constants |
| Modula-3 (Language Definition, 1989, section 2.6.8) | sets, arrays, records; constant when every element is | `R{f := e, ...}` or positional `R{e, ...}` ("exactly as in a procedure call"), `A{e, ...}`, `A{e, ..}` repeats the last element; `S{...}` for a set too | `RecordElt = [Id ":="] Expr`; the bindings are rewritten as for a call: a field with a default may be left out, every other one must be bound, each exactly once. An array constructor gives exactly the fixed array's length (or uses `..`); an open array type may be the constructor's type, its length then the number of elements. Record fields have no export marks (only opaque types hide), so there is no visibility rule |
| Ada (for comparison) | records and arrays | `(X => 1, Y => 2)`, `(others => 0)` | named or positional; every component must be given (`others` covers the rest); a private type has no aggregate outside its package |

What the survey says about the decisions:

- `T{...}` is Modula-3's form, ISO Modula-2's (the one Oberon+ points to
  for itself) and Micron's. Modula-3 writes a set's type before its
  braces too, `S{...}`; Oberon-2's untyped set constructor stays as it is. It is unambiguous in Oberon-2: a designator is never
  followed by `{` in an expression today, and a set constructor stands
  alone.
- Named components are Modula-3's own keyword bindings, `f := e`, which
  is what poc already writes for initializers; Micron writes `f: e` and
  Ada `F => e`. (`:` would read as a declaration in Oberon, and `=` as a
  comparison.) Modula-3 also allows positional bindings; poc does not
  (decision 2).
- Omitted elements taking their defaults is Micron's rule, and Modula-3's
  for a field with a default. In poc every field has one (its initializer,
  or zero, since every variable starts at zero), so every field may be
  left out. Modula-3 requires a fixed array's every element (or `..`
  to repeat the last); Ada and ISO Modula-2 require every component.
- The rule for hidden and read-only fields is Micron's, and close to
  Ada's private types.
- Of the languages surveyed, Active Oberon (constant arrays), Modula-3,
  ISO Modula-2 and Micron allow a constructor in a constant, as poc will
  (decision 5). `CONST origin = Point{x := 0, y := 0}` fits Oberon as it
  is: a constant never states its type, which comes from its expression
  (`CONST s = {1, 2}` is a `SET`), and a literal names its type. (Modula-3's
  `ConstDecl = Id [":" Type] "=" ConstExpr` makes the type optional.)
- Modula-3's types are equivalent by structure ("two types are the same if
  their definitions become the same when expanded"), so its constructor
  takes any type expression, named or not: `Constructor = Type "{" ...`.
  Oberon-2's are equivalent by name, so an anonymous type before `{`
  would be identical to no other type; hence a literal names its type.
  (poc's rule for assigning fixed arrays, which looks only at the element
  type and the length, Phase 11 A21, would let an anonymous array literal
  through; a record literal would not, and one rule for both is simpler.)

## Rules in detail

- **The type** is a named record type, or a named array type of fixed
  length (an open array type has no length to fill). A pointer type, an
  open array or an anonymous type cannot be written before `{`.
- **Record elements**: each is `name := expression`, where `name` is a
  field of the record type or one of its base types, written at most once,
  and the expression is assignment compatible with the field (Appendix A).
- **Array elements**: positional, at most the array's length, each
  assignment compatible with the element type.
- **Nested literals**: an element whose type is a record or array type
  may be written as a literal of that type, `Point{...}`. Inside a literal,
  where the element's type is known, the type name may be left off:
  `Matrix{{1, 0}, {0, 1}}` (`Matrix = ARRAY 2 OF ARRAY 2 OF REAL`), which is
  how an element of an anonymous array type gets a literal at all. A bare
  `{...}` is a set constructor wherever the expected type is a set type.
- **A string** is an element of an `ARRAY n OF CHAR` field or element, as
  in assignment.
- **Evaluation**: the elements in the order written, each once; then the
  defaults of the omitted ones, as `NEW` makes them. (Settled otherwise,
  2026-10-03: the value is made as a variable is, every default first,
  and then the elements are assigned in the order written; an imported
  type's defaults exist only as one procedure that applies all of them.)
- **Where a literal may stand**: wherever an expression of its type may:
  the source of an assignment (including `p^ :=` and a field), a value
  parameter (an open array parameter included, by the array's elements), a
  variable or field initializer. Not as a `VAR` parameter (it is not a
  variable), and not as a function result,
  which Oberon-2 does not allow for a structured type anyway.
- **Type extension**: a literal of an extension assigned to a variable of
  its base type is projected, as any record assignment is.

## Structured constants

Proposed here, and settled in Phase 14 step 1 (2026-10-03) as
`doc/language-extensions.md` says, with two changes: an omitted field
of an imported type has a constant default when the `.sym` file gives
its value, and an exported constant's type may have hidden fields.

- **What is constant**: a literal is a constant expression when every
  element written is one, and every omitted field's default is: a field
  initializer (Phase 11 D17 allows any expression) that is not constant
  makes a literal that leaves the field out non-constant, and so not
  allowed in a `CONST`. A pointer or procedure element can only be NIL.
- **Where one may stand**: wherever a read-only variable of its type may:
  read, assigned from, passed as a value parameter or an open array
  parameter. Not as a `VAR` parameter, nor to `SYSTEM.ADR`, and never
  assigned to.
- **Selecting from one**: `origin.x`, and `table[3]` with a constant
  index, are constant expressions, folded like any other (so a table of
  constants can give a `CASE` label or an array length). With an index
  that is not constant, it is an ordinary read, of the constant's copy in
  memory, index-checked as usual. `LEN` and `SIZE` of one are constants
  already.
- **No comparison**: `=` and `#` stay undefined on records and arrays, as
  in the report.
- **Exported**: the `.sym` file writes it as its literal,
  `Origin* = Point{x := 0, y := 0};`, every element given (defaults
  included), so the importer folds `M.Origin.x` without the exporter's
  field initializers. The writer puts structured constants in a second
  `CONST` section after `TYPE`, since a literal names a type and the
  reader declares before use (`Oberon2.pdf`'s `DeclSeq` allows the
  sections in any order). The type must be visible to the importer: an
  exported constant of a type that is not exported is an error.
- **In memory**: each module that uses one in a way that needs memory
  (passing it, indexing it with a variable) has its own private constant
  copy, made from the value, as a scalar constant is folded into each
  module rather than linked from its exporter.

## What the implementation touches

| Part | Change |
|---|---|
| `SyntaxTree` | a literal node: the type's designator, and its elements, each an optional field name and an expression (a nested bare `{...}` kept as a list until its type is known) |
| `Parser` | in `ParseFactor`, a designator followed by `{` is a literal; elements are `ident := expression`, `expression`, or a bare `{...}` |
| `SemanticActions` | the type rules above; the visibility rule (decision 4); a nested bare `{...}` resolved as a set or a literal by the expected type; `-strict`; a structured constant: its declaration, its use as a read-only operand, selection from it |
| `Types`, `ConstantEvaluator` | a structured `Value`: its type and its elements' values, every field or element filled in; constant folding of a literal and of a selector applied to a structured constant |
| `ModuleInterface` | an exported structured constant written as a literal, in a `CONST` section after `TYPE`, and read back through the parser |
| `LLVMCodeGenerator` | as built (step 4): every literal is made in a stack slot of its own, allocated in the function's entry block so that a loop does not grow the stack, zeroed and initialized as a variable is (`InitializeAt`), then its elements stored in order, a nested literal without its type name in its element's place; it is loaded from there as a value, or its address passed to an open array or copied from (`CopyArrayBlock`). A slot holding pointers is on the stack the collector scans. A structured constant is a private constant global of each module that uses it, addressed like a variable, so selecting from it with a variable index or passing it needs nothing more; it can hold only NIL pointers. (The first plan, an LLVM constant aggregate or an `insertvalue` chain for a record literal, was dropped: making a literal as a variable is is what memory and the initialization procedures already do.) |
| Documentation | a section in `doc/language-extensions.md` and its one-line summary in `AGENTS.md`; the User's and Reference Guides |
| Fixtures | literals accepted and run (records, arrays, nested, omitted elements, defaults from field initializers, arrays of records, open array parameters, extension); literals rejected (unknown or repeated field, too many elements, incompatible element, hidden or read-only field, a non-constant element in a `CONST`, a structured constant as a `VAR` parameter or assigned to, an exported constant of a hidden type, `-strict`); structured constants folded, selected from, passed, and exported and imported through `.sym`; voc cannot cross-check any of it |

## Open questions

Decided 2026-10-03: none of these is in Phase 14. Indexed elements with
ranges (`[48..57]: 1`) are the one worth reconsidering once real tables
show the need.

- Indexed array elements (Micron's `[i]: e`), a repeat count (ISO
  Modula-2's `e BY n`) or Modula-3's trailing `..`: not in the first
  version; an array is filled from the start, and the rest takes its
  default.
- A literal of an open array type, its length the number of elements
  (Modula-3, Micron): not in the first version; a value parameter of an
  open array type already takes a literal of a named fixed array type.
- Whether a bare `{...}` should also be accepted where the type comes from
  outside a literal (the left side of an assignment, a formal parameter),
  as Micron infers it: not in the first version, so a literal always
  begins with its type's name.
