# Survey: initializers on `VAR` declarations (A23) and record/array literals (A24)

Phase 11 inventory items A23 and A24, from `000-todo.org`:

- "Initializers for variable declarations consisting of := after the type,
  followed by an expression."
- "Oberon-2 has syntax for sets literals; it would be good have syntax for
  record and array literals, too."

Surveyed 2026-09-26 in the sources under `/usr/local/sw/src/lang/Oberon`,
one parser at a time. The Modula-3 and ISO Modula-2 entries are background
from memory, not checked against a local copy of either report.

## What `Oberon2.pdf` and poc have now

- `VariableDeclaration = IdentList ":" Type.` No initializer.
- The only structured value that can be written down is a set, `{1, 3..5}`,
  and a string, which is an `ARRAY OF CHAR` constant. `CONST` declarations
  are of basic types, sets and strings only.
- What a variable holds before its first assignment (poc today):
  - globals: zero (LLVM `zeroinitializer`);
  - heap blocks (`NEW`): zero-filled;
  - pointers, locals included: NIL, as `Oberon2.pdf` §6.4 requires (a
    local pointer is stored NIL on entry);
  - **every other local: nothing.** Its `alloca` is not stored to. Until
    D13 that meant whatever was on the stack; with `-O2` the default (Phase
    11 D13), reading it before assigning it is undefined behavior for LLVM,
    so the optimizer may assume any value, or none. voc is the same (a C
    local, uninitialized).

## A23: initializers on variable declarations

| Dialect | Initializers? | Form and rules |
|---|---|---|
| voc | no | `IdentList ":" Type` (`OPP.Mod`; its `:=` in declarations is `IMPORT M := Module` only) |
| Ofront+ | no | the same (`OfrontOPP.cp`) |
| oo2c | no | `IdentList ":" Type` (`OOC/Parser.Mod`) |
| Component Pascal / BlackBox | no | `VariableDeclaration = IdentList ":" Type.` (CP report) |
| Oberon+ | no | `VariableDeclaration = IdentList ":" type` (its specification); variables start at zero or NIL |
| obc | no | `defids COLON texpr` (`parser.mly`) |
| OBNC, Oberon-07 | no | Oberon-07 report |
| **A2 / Active Oberon (Fox)** | **yes** | `VAR a := 5, b: INTEGER;` - the initializer follows *each name*, before the colon (`FoxParser.VariableNameList`). It must be a **constant expression** (`FoxSemanticChecker`: `ConstantExpression(variable.initializer)`). A global's value is static data; a local is assigned on entry to its procedure; a **record field's initializer is its default**, filled in whenever a record of that type is created |
| Modula-3 (background) | yes | `VAR x, y: T := e;` - after the type, any expression, each variable of the list gets its own evaluation; the type may be left out (`VAR x := e;`) and then is `e`'s. Record fields take defaults the same way |
| ISO Modula-2 (background) | no | |

So in the Oberon line only Active Oberon has them, and only with constant
values; the form `000-todo.org` asks for (after the type) is Modula-3's.

**What adopting it would mean for poc** (not decided):

- Syntax: `VAR x, y: T := e;`, the `000-todo.org` form, or A2's per-name
  form. After the type reads naturally and gives one initializer for the
  list.
- Which expressions: constant only (A2) or any (Modula-3). A constant one
  can be static data for a global; any expression means evaluating it at
  run time - for a local on each entry, before the body, in declaration
  order; for a global at the start of the module body. Desugaring into
  assignments in the front end (the existing proposal in the inventory)
  handles both, and makes the rules exactly those of assignment.
- Where: variables only, or also record fields (A2), which would mean
  defaults applied by `NEW` and for every record variable.
- It is an extension, so `-strict` rejects it, and a program using it no
  longer compiles under voc (poc's own source cannot use it: voc builds
  Stage 0).

## A24: record and array literals

| Dialect | Array literal | Record literal |
|---|---|---|
| voc, Ofront+, oo2c, CP/BlackBox, obc, OBNC/Oberon-07 | no (strings only) | no |
| oo2c | typed *set* constructors (`type{...}`), no others | no |
| **A2 / Active Oberon** | **`[1, 2, 3]`, nested for more dimensions** - a `MathArray` factor (`FoxParser`), whose type is one of Active Oberon's mathematical arrays (`ARRAY [n] OF T`, a separate kind of array with its own operators) | no |
| Oberon+ | no: listed under TODO in its specification, as `[1, 2, 3]` or ISO Modula-2's `ArrayType{1, 2, 3}`, "which would also support record literals" | no (same TODO) |
| ISO Modula-2 (background) | `T{1, 2, 3}` value constructors, for arrays, records and sets | `T{a, b}`, positional |
| Modula-3 (background) | `T{1, 2, 3}`, `T{1, ..}` repeats the last element | `T{f := 1, g := 2}`, named or positional, fields with defaults may be left out |

No Oberon dialect has record literals, and the one array literal (A2's)
belongs to a kind of array poc does not have.

**What adopting it would mean for poc** (not decided): a typed form such as
`T{...}` (the type is needed: an untyped `[1, 2]` does not say the element
type or, for a fixed array, the length); `CONST` declarations of structured
type, which `Oberon2.pdf` does not have, and so structured constants in
`.sym` files; open arrays and pointers inside literals; positional or named
fields, and what a record extension's literal contains. It is a new kind of
expression through the whole front end, the `.sym` format and the backend -
by some distance the larger of the two.

## A related finding

Uninitialized non-pointer locals (above) are the case A23 would mostly be
used for, and the one that changed with D13: at `-O2` a read before the first
assignment is undefined. Zeroing every local on entry, as globals and heap
blocks already are, would make it defined everywhere; the optimizer removes
the stores that a later assignment makes dead. This is separate from A23 and
not in the inventory yet.

## Decisions (user, 2026-09-26)

- **A23: adopted** as `VAR x, y: T := e`, any expression, **evaluated once
  for each variable** of the list (so a function call in it is made once per
  variable), before the body, in declaration order; only names declared
  before the `:=` are visible; variables only; `-strict` rejects it.
  `doc/developer/language-extensions.md`, "Variable initializers".
- **Record-field initializers**: a separate item, Phase 11 D17, then decided
  (user, 2026-09-26): any expression, not A2's constants; one
  initialization procedure per record type, with the `.sym` file saying only
  that a field has an initializer. Done: `doc/developer/language-extensions.md`,
  "Record field initializers".
- **A24: moved to Phase 17**, a new phase for further extensions to
  Oberon-2 (`PLAN.md`).
- **The related finding: done** as Phase 11 D16 - every local starts at zero.

