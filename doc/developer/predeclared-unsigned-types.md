# Predeclared unsigned types

A plan for `SHORTCARD`, `CARDINAL`, `LONGCARD` and `HUGECARD`
(`000-todo.org`): unsigned types with as many bits in each size model as
`SHORTINT`, `INTEGER`, `LONGINT` and `HUGEINT`, predeclared like them
rather than in `SYSTEM`, and separate from the signed integers. Its entry
in `PLAN.md` is "Ongoing language enhancements", 5. Nothing here is
implemented yet. Decisions 5 and 6 add to the language beyond what was
asked; the user accepted them on 2026-11-01.

The probes below were run on 2026-11-01 with poc 0.10.1, and the code was
read at `f4d36fc`.

## What is there now

Since 0.6.0 poc has `SYSTEM.CARD8`, `CARD16`, `CARD32`, `CARD64` and
`SYSTEM.CARD`, with their rules in `language-extensions.md`, "Unsigned
integer types". The survey behind them is `doc/research/unsigned-survey.md`.
`Types.BasicTypeDesc` has `unsigned`, and nearly everything goes through
`Types.IsCardinal`, `IntegerBytes` or `Order`, not through the types' names.
So the rules and most of the code generation already apply to any new
unsigned type. The work is in the few places that name the types, and in
the two things below that the `SYSTEM` types never needed.

**A program with no `SYSTEM` import cannot cross between the families.**
`SYSTEM.VAL` is the only conversion. It is also how a `.sym` file writes an
unsigned constant (`c* = S.VAL(S.CARD16, 65535)`), through the name the
module imports `SYSTEM` by. A module that says `CONST c* = MAX(CARDINAL)` may
not import `SYSTEM` at all. See decision 5.

**A program with no `SYSTEM` import cannot read one.** `In.Card` takes `VAR
c: SYSTEM.CARD64`, and a `VAR` actual must be the same type (the probe:
`HUGEINT` to a `VAR SYSTEM.INT64` is an error). See decision 6.

## The types

| Type | `-O2` bytes | `-OC` bytes | Range under `-O2` | Range under `-OC` |
|---|---|---|---|---|
| `SHORTCARD` | 1 | 2 | 0..255 | 0..65535 |
| `CARDINAL` | 2 | 4 | 0..65535 | 0..4294967295 |
| `LONGCARD` | 4 | 8 | 0..4294967295 | 0..2^64 - 1 |
| `HUGECARD` | 8 | 8 | 0..2^64 - 1 | 0..2^64 - 1 |

## Decisions

1. **Four new types, not aliases of `SYSTEM.CARDn`.** They stand to `CARDn`
   as `SHORTINT` stands to `INT8`: the model's types beside the exact ones.
   `SYSTEM.CARDn` stay, for foreign interfaces, where the width must not
   follow a flag. An alias could not work for three of the four, since
   each model would need a different one.

2. **`LONGCARD` and `HUGECARD` stay distinct under `-OC`**, as `LONGINT` and
   `HUGEINT` do, though both are 8 bytes. `HUGECARD` includes `LONGCARD`, and
   `LONGCARD := h` is an error, as `LONGINT := HUGEINT` is under `-OC`
   (probed).

3. **Every rule of the `SYSTEM.CARDn` applies.** A family apart, included in
   `REAL`, mixing with signed an error, wrapping arithmetic, unary minus
   allowed, `ABS` the identity, unsigned comparison, `DIV`, `MOD`, `ASH` and
   `LSH`, a non-negative constant that fits usable, no decimal literal above
   `MAX(HUGEINT)`, a hexadecimal pattern where an 8-byte type takes it. A
   one-byte `SHORTCARD` (`-O2`) goes to `SYSTEM.BYTE`, as `SHORTINT` and
   `CARD8` do. `ORD`, `LEN` and `SIZE` stay signed.

   `Order` already gives this inclusion, with no change, by placing the
   `CARDn` among the model types as it does the `INTn`, so the two kinds mix
   freely. `CARD8 + CARDINAL` needs no conversion:

   - `-O2`: `SHORTCARD` = `CARD8` < `CARDINAL` = `CARD16` < `LONGCARD` =
     `CARD32` < `HUGECARD` = `CARD64`
   - `-OC`: `CARD8` < `SHORTCARD` = `CARD16` < `CARDINAL` = `CARD32` <
     `LONGCARD` < `HUGECARD` = `CARD64`

   `=` means each includes the other. They are still different types, so a
   `VAR` parameter tells them apart, and between two such operands the left
   one's type is the result, as for `INT16 + INTEGER`.

4. **`LONG`, `SHORT` and a constant's widening stay among the names the
   operand used.** `LONG` of a model type is the narrowest model type
   strictly wider, else `HUGECARD`. `SHORT` is the widest strictly narrower,
   else `SYSTEM.CARD8`, the floor the signed family has in `INT8`. So under
   `-OC`, `SHORT(HUGECARD)` is a `CARDINAL`, skipping `LONGCARD`, as
   `SHORT(HUGEINT)` is an `INTEGER` there (probed). `LONG` and `SHORT` of a
   `CARDn` do not change. With `c` a `CARDINAL` under `-O2`, `c + 70000` is
   a `LONGCARD`, not a `CARD32`: both are right, but a program that
   imports no `SYSTEM` should not see `SYSTEM` in its error messages.

5. **A predeclared `VAL(T, x)`, for the crossing.** Without it "available everywhere" stops at the first `INTEGER`, since a
   `CARDINAL` could be mixed with one only by importing `SYSTEM`. `T` is an
   integer type of either family, and `x` an integer of either family,
   constant or not. The name and form are ISO Modula-2's, which the survey
   sets against `CAST`.

   - On integers it gives the bits `SYSTEM.VAL` gives (probed): extended
     by `x`'s own signedness, truncated to `T`. So `VAL(LONGCARD, h)` narrows
     a `HUGECARD` under `-OC`, and `VAL(HUGECARD, i)` of an `INTEGER` -1 is
     `MAX(HUGECARD)`. The two can share their code generation.
   - It differs in five ways. It needs no import. It takes integers only,
     where `SYSTEM.VAL` also takes reals, pointers and procedures. It says
     the value should fit: `-range-checks` traps one that does not (14), as
     for `SHORT`, and `SYSTEM.VAL` never traps. A constant that does not
     fit is a compile-time error, where `SYSTEM.VAL(SYSTEM.CARD8, 300)`
     quietly folds to 44. And it is a constant for any integer `T`, where
     `SYSTEM.VAL` is one only for an unsigned `T`.
   - `-strict` rejects it.

   It also settles the `.sym` file: `c* = VAL(CARDINAL, 65535)` needs no
   import. `S.VAL(S.CARD16, ..)` stays for the `CARDn`, so no module's
   interface text or key changes unless it uses the new types.

   One limit: `.sym` holds exported names, so a module that exports its own
   `VAL` hides this one in its own interface, as a module exporting
   `HUGEINT` already would. The writer refuses that case with a message
   saying why, and only when such a constant is exported.

6. **`In.HugeCard` and `InStr.HugeCard`**, taking `VAR c: HUGECARD`. `Card`
   stays. `Out`, `Err` and `OutStr` need nothing:
   their `Card` and `CardHex` take a `SYSTEM.CARD64` by value, which includes
   all four. These procedures go in `rtl/llvm` and `rtl/vax`; Stage 0 does
   not compile `In` or `InStr` (`rtl/voc` has neither).

7. **`-strict` rejects all four**, in the command-line module's own source,
   by `MarkExtension(Universe, ...)`, as for `HUGEINT`. A strict program that
   declares its own `CARDINAL` is unaffected, because its declaration is
   found first.

## Compatibility

Four new names in the Universe, five with `VAL`. A declaration of one still
hides it, so old programs go on compiling, with one exception: **a
declaration of one after a procedure becomes an error**, "a declaration after
a procedure cannot reuse a name visible from an enclosing scope" (the rule of
A22; probed with `LONGINT`). That is an extension's rule, not the report's,
and it stays.

The names are used in no `.Mod` under `src`, `rtl`, `tools`, `test` or
`doc/examples` (`vax-cardinal`'s matches are its own module name), nor in
any other project under `~/Repos/Oberon` outside `vishap-bugs`.

poc's own source cannot use the types, since voc has none of them and
Stage 0 compiles it, and `make check-strict` keeps it so. It only names the
new `Types` variables.

## What changes

Most of this follows from `Order` and `IsCardinal`, so the list is short.

| File | Change |
|---|---|
| `src/front/Types.Mod` | `ShortCard*`, `Cardinal*`, `LongCard*`, `HugeCard*`: `NewCardType(<the rank>, 0)` |
| | `IntegerBytes`: `ELSIF bt.unsigned THEN RETURN addressBytes` must apply to `SYSTEM.CARD` alone (`bt.rank = addressRank`), or every new type is taken as word-sized. This is the trap of the work |
| | `LongerInteger`, `ShorterInteger`: decision 4 |
| | `ConstantOperandType`: climb by `LongerInteger`, ending at 8 bytes, not by `CardOfBytes` and `t # Card64` |
| | `AssignmentCompatible`: `SYSTEM.BYTE` takes a one-byte `ShortCard` |
| | `TypeName`, `Describe` |
| `src/front/SymbolTable.Mod` | `InsertPredeclared` and `MarkExtension`, four names and `VAL` |
| `src/front/MemoryLayout.Mod` | `Size` by the size model, as for the signed four |
| `src/front/SemanticActions.Mod` | `IsByteVarFormal` |
| `src/front/PredeclaredProcedures.Mod`, `ConstantEvaluator.Mod` | `VAL`, checked and folded |
| `src/front/ModuleInterface.Mod` | an unsigned constant whose type is a Universe name: `VAL(CARDINAL, k)`. The present code scans the bound name for a `.`, which such a name lacks, and would run off the array |
| `src/back/llvm/LLVMTypes.Mod` | the `i8`..`i64` chain, by the size model |
| `src/back/llvm/LLVMCodeGenerator.Mod`, `src/back/vax/VaxCodeGenerator.Mod` | `VAL`, on the widening and narrowing `LONG` and `SHORT` use, with `-range-checks` |
| `rtl/llvm/In.Mod`, `InStr.Mod`, `rtl/vax`'s | `HugeCard` |

Nothing else should need it, by reading: `MAX` and `MIN` reach
`ConstantEvaluator`'s `IsCardinal` branch, `WrapToCard` and `CardFits` go by
`IntegerBytes`, debug information goes by `IsCardinal` (LLVM,
`DW_ATE_unsigned`) and by size (VAX, `DstType`), and `.sym` spells a basic
type by its Universe name. The tests must prove each of these, not assume it.

## Plan

Each step is checked on atla, cymoril, artos and alerik before it is
committed. rackhir runs after steps 2 and 4, since arithmetic and layout
are involved, and at the end.

1. **The decisions.** Write the section in `language-extensions.md` and its summary in `AGENTS.md`, under the same
   heading.

2. **The types** (`Types`, `SymbolTable`, `MemoryLayout`, `LLVMTypes`,
   `SemanticActions`). The table above but for `VAL`, `.sym` constants and
   `In`. Fixtures, each under both size models:
   - `semantic-predeclared-cardinal`: every inclusion above, both ways;
     mixing with signed refused; `LONG`, `SHORT` and `c + 70000` shown by the
     type an error message names; `SYSTEM.BYTE`, with `SHORTCARD` taken under
     `-O2` only; a user's own `CARDINAL`; the late declaration refused;
   - `semantic-strict-predeclared-cardinal`;
   - `llvm-predeclared-cardinal`: `MAX`, wrapping, comparison, `DIV`, `MOD`,
     `ASH`, `LSH`, `FOR` to `MAX`, `CASE`, array indexes, `SIZE`, and `Out`
     of each, with no `SYSTEM` import.

3. **`VAL` and `.sym`.** `VAL` in the front end and the LLVM back end;
   `ModuleInterface`. Fixtures:
   - `llvm-predeclared-val`, with its traps under `-range-checks`, and
     `semantic-reject-predeclared-val`, with `semantic-strict-*` covering it;
   - `llvm-predeclared-cardinal-import`: constants, types and fields across
     modules, the importer and the exporter importing no `SYSTEM`, and
     `MAX(HUGECARD)`, whose value is written as a pattern;
   - that the `.sym` of `llvm-cardinal-import` is unchanged.

4. **The VAX.** `VAL`, and `vax-predeclared-cardinal` and
   `vax-predeclared-val` run on the guest, under both size models.
   `vax-cardinal`'s reviewed `.mar` should not change: if it does, that is a
   bug in step 2. New `.mar` output goes to the user for review.

5. **`In` and `InStr`.** `HugeCard` in both runtimes, with `llvm-in-extra`,
   `llvm-instr`, `vax-in-extra` and `vax-instr` extended. `tools/rtl-reference
   update` afterwards. Run `make check-seed`, and find out whether a
   `BOOTSTRAP_POC` older than this release can still build the runtime,
   which now names a type it lacks. If not, `DEVELOPER.md` says so.

6. **Documents.** The Reference Guide's type table and unsigned section, the
   predeclared procedures, the options' `-strict` and `-range-checks` text;
   the User's Guide, where it mentions unsigned types; `doc/poc.1` if its
   `-strict` text lists them; `src/front/README.md`; `PLAN.md`'s entry marked
   `[done]`; `doc/research/unsigned-survey.md`'s closing note extended by
   what was decided here.

Steps 2 and 3 cannot be released apart: without step 3 a module exporting a
`CARDINAL` constant writes a `.sym` it cannot read. So step 2's fixtures
stay clear of exported constants, and both go into one release. Step 2 can
refuse such a constant with a message until step 3 is committed.
