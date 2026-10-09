# Language extensions beyond Oberon2.pdf

poc's own extensions and the choices it made where `Oberon2.pdf` is silent -
what a program compiled by poc can observe. Moved here from `AGENTS.md`
(2026-09-25), which keeps a one-line summary of each section under the same
heading; references elsewhere to `AGENTS.md`, "\<section\>" mean the section
of the same name here.

This is the design document for each extension: why it was adopted, what
was considered, and how poc builds it. The Reference Guide
(`doc/reference-guide.md`, Phase 13 step 7) documents each one as actually
implemented, for a programmer (user, 2026-10-02).

## HUGEINT (implemented)

An 8-byte signed integer, predeclared alongside `Oberon2.pdf`'s own basic
types (§6.1). Adopted directly from voc's identically-named, identically-
sized extension (see `AGENTS.md`, "Reference implementation: Vishap Oberon (voc)") rather than inventing a
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
default byte widths (or `-OC`'s, under poc's own `-OC` flag — see
`AGENTS.md`'s voc section on `-O2`/`-OC`), and reports "integer
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
step 4 (2026-09-19) and the rest done in Phase 10 step 7 (2026-09-20) - see
"SYSTEM subset (implemented)" below. Two adjustments beyond the report's
own text follow from decisions made elsewhere in this file: `ADR`/`GET`/
`PUT`/`MOVE`'s address arguments use `SYSTEM.ADDRESS`, not `LONGINT` (see
"SYSTEM subset (implemented)" below - an address-width concern, independent of
`HUGEINT`), and `LSH`/`ROT`'s "`x`: integer, CHAR, BYTE" argument category
includes `HUGEINT` alongside `SHORTINT`/`INTEGER`/`LONGINT`, since it is a
genuine additional integer type by the same Appendix A definition above.

## SYSTEM subset (implemented)

`IMPORT SYSTEM` binds a pseudo-module (no source, no `.sym`;
`SymbolTable.SystemScope`) offering `ADDRESS`, `ADR`, `GET`, `PUT`, `VAL`
and `MOVE`, pulled forward from Phase 10 step 7 because the garbage
collector (`rtl/llvm/GarbageCollectedHeap.Mod`, written as ordinary Oberon-2
over raw addresses) needs them. `SYSTEM.ADDRESS` is deliberately **not**
voc's `LONGINT` alias: it is its own integer type, as wide as a pointer on
the target, and placed among the integers by that width (Phase 11): as wide as
a `LONGINT` or narrower and it is the same as `SYSTEM.INTn` - two types of one
width include each other, a wider includes a narrower and not the reverse.
So a `LONGINT` is assignable to an address where it is no wider (always,
except under `-OC` on a 32-bit target, where it is 8 bytes to the address's
4 and needs `SYSTEM.VAL(SYSTEM.ADDRESS, ...)`), a mixed `ADDRESS`/`LONGINT`
operation is done at the wider width, and on a 64-bit target `ADDRESS` and
`HUGEINT` include each other (`semantic-address-width` has the whole
table). An `ADDRESS` and any integer type of its width include each other
(2026-10-08, `PLAN.md`, "Ongoing language enhancements" 2): before, under
`-OC` on a 64-bit target, an `ADDRESS` ranked with `HUGEINT` and was not
assignable to the 8-byte `LONGINT`, so under `-OC` an `ADDRESS` is now
assignable to a `LONGINT` on every target. `GET`/`PUT` access memory with no alignment assumption;
`PUT(a, x)` stores `x` at `x`'s own type, so a bare numeral is stored at
its minimal integer type's width (`PUT(a, 5)` writes a `SHORTINT`-sized
value under `-O2`). `VAL(T, x)` between scalars of different widths
sign-extends or truncates - the report leaves it undefined and voc warns.
`GET`, `PUT` and `MOVE` are volatile accesses (Phase 11 D13, 2026-09-25): at
any `-opt` level each happens once, where the program says, and one at an
unmapped address - address 0 included, which LLVM would otherwise take as
unreachable - still ends the program with `SIGSEGV`.

Phase 10 step 7 added the rest (`PLAN.md` step 7 has the full account; probed
against real voc 2026-09-20). What a program can observe:

- **`SYSTEM.BYTE`** is one byte; `CHAR` and `SHORTINT` are assignable to it,
  not back (use `VAL`). A `VAR x: ARRAY OF BYTE` parameter takes a variable of
  any type, its hidden length the actual's size in bytes. Since Phase 12
  step 5d (decided with the user 2026-10-02, for voc's `Files.Read`): the
  Oakwood Guidelines' rule (1.2.5), a parameter of type `BYTE` takes a
  `CHAR`, a `SHORTINT` or a `BYTE`, so a `VAR x: BYTE` one takes such a
  variable, and a `BOOLEAN` too, as voc's. A `SHORTINT` only where it is one
  byte, as Oakwood's and the report's Ceres have it (and voc): under `-O2`,
  not `-OC`, for assignment too; an integer constant only in -128..127
  (under `-OC` a constant's minimal type is a two-byte `SHORTINT`). voc
  also takes a `SYSTEM.INT8` variable for a `VAR BYTE`; poc does not.
  Fixture `semantic-system-byte-params`.
- **`SYSTEM.PTR`** is a pointer to an empty record: any pointer is assignable
  to it and a `VAR p: PTR` takes any pointer variable; it may be compared
  with any pointer or `NIL` (voc rejects that). **A `PTR` is opaque**: it
  cannot be dereferenced or `NEW`'d (voc rejects both too, errs 57 and 111),
  and **unlike voc it cannot be type-guarded, `IS`-tested or used as a `WITH`
  variable** (voc accepts these for a pointer to a record; for a pointer to an
  array its generated C does not compile) - assign it to a typed pointer
  first. Decided with the user 2026-09-21 (Phase 11, A10): a heap block's tag
  is read through to test its type, which is unsound for a block with tag 0
  (`SYSTEM.NEW`) or an array descriptor. **A guard, `IS` or `WITH` on a
  pointer to an array is a compile error too** (voc's err 85): only records
  extend, so such a test could only name the pointer's own type. It used to
  pass the checker, then either "cannot lower" in the backend or, for `WITH`,
  compile and always exit 6 (`semantic-reject-guard-array-pointer`).
- **`LSH`/`ROT`** work at `x`'s own width and the result has `x`'s type (a
  shifted `CHAR` is a `CHAR`; voc gives a signed integer); a negative count
  goes the other way, and a `LSH` count of the width or more is 0, a `ROT`
  count is taken modulo the width - defined, where voc's are C's undefined
  shifts.
- **`BIT(a, n)`** is a bit string starting at `a`: bit `n` mod 8 of the byte
  at `a + n DIV 8` (floored), bit 0 the low bit of the byte at `a`. Defined
  for every `n` - 32 and up are the following bytes, a negative `n` the bytes
  before `a` - and only the one byte is read, no alignment assumed. Decided
  with the user 2026-09-21 (Phase 11, A11). On a little-endian machine, every
  target poc has, it is voc's result for `n` in 0..63 (voc's `__BIT` reads a
  64-bit word, undefined beyond) and A2's, and it is what the VAX's `BBS`/
  `BBC` do with their signed bit position (VAX Architecture Handbook, 1986,
  ch. 4). Until then poc tested a 32-bit `SET`-sized word and answered `FALSE`
  outside 0..31, which the docs called voc's - true only below 32.
- **`SYSTEM.NEW(v, n)`** allocates `n` zero-filled bytes for any pointer
  variable, untraced by the collector (tag 0: kept while something points at
  it, never scanned inside, exactly voc's `NEWBLK`/`NoPtrSntl`, decided with
  the user 2026-09-21 - it must not hold the only reference to anything);
  `n <= 0` or too large traps
  (exit 7, as `NEW` of an open array), no heap leaves `v` NIL. Told from the
  ordinary `NEW` by the `SYSTEM.` qualifier.
- **`SYSTEM.INT8/16/32/64`** are integers of exactly 1/2/4/8 bytes under both
  size models (Phase 11; they were aliases of the `-O2` types, so under `-OC`
  `SYSTEM.INT32` was 64 bits, which is what kept a C `int` from being spelled
  right - and poc built with `-OC` from running on a 32-bit target). They are
  distinct types, and as in voc, where inclusion goes by size, they take their
  place among `SHORTINT`/`INTEGER`/`LONGINT`/`HUGEINT` by byte width
  (`Types.Order`): two of one width include each other (`INT32` and `LONGINT`
  under `-O2`, `INT32` and `INTEGER` under `-OC`; `INT64` and `HUGEINT` under
  both), a wider includes a narrower and not the reverse. An integer constant
  whose *value* fits is assignable to any of them, since a constant's own type
  is its minimal one under the model. `MAX`/`MIN`/`SIZE` work. `LONG` and
  `SHORT` of them, and of `HUGEINT`, go by byte width as in voc (probed under
  both models, Phase 11 step 2): `LONG(x)` is the narrowest of `SHORTINT`/
  `INTEGER`/`LONGINT` strictly wider than `x`, else `HUGEINT`; `SHORT(x)` the
  widest strictly narrower, else `SYSTEM.INT8`. So `LONG` of an `INT32` is a
  `LONGINT` under `-OC` and a `HUGEINT` under `-O2`. `LONG(LONGINT)` and
  `SHORT(SHORTINT)` stay errors, as in the report (voc accepts both). An integer
  *constant* met by an `INT8` in `+ - * DIV MOD` takes the `INT8`'s type when
  its value fits it (Phase 11 step 3), so `b := b + 1` works under `-OC`, where
  a constant is otherwise at least two bytes; `b + 200` or `b + 128` is a
  `SHORTINT` or wider and is not assignable back, as in voc (probed under both
  models, `semantic-system-fixed-width`, `llvm-system-int8-constants`). The
  operation is done at one byte, so an overflow of the *sum* (`l := b + 100`
  with `b = 100`) wraps as it does for every narrow type, where voc's C
  promotes to `int` first - undefined in the report. `CC`, `GETREG` and
  `PUTREG` are not implemented: they
  name a machine's registers and condition codes, which LLVM IR has none of.

## `SYSTEM.SET32` and `SYSTEM.SET64` (implemented, Phase 11 step 6)

`PLAN.md` Phase 11 step 6 has the full account; probed against voc's source and
binary 2026-09-21 (decided with the user). A `SET` has 32 bits under **both**
size models, as in voc (`OPM.Mod`: `-O2` 1/2/4/4 bytes, `-OC` 2/4/8/4) - it
used to follow `LONGINT` and be 64 bits under `-OC`, so `MAX(SET)` was 63 there.
What a program can observe:

- **`SYSTEM.SET32` is `SET`; `SYSTEM.SET64` is a distinct 8-byte set** with
  elements 0..63 (`MAX` 63, `MIN` 0, `SIZE` 8, 64-bit LLVM integer). Neither
  is ordered (`<` is an error) and both take `=`, `#`, `IN`, `+ - * /`, unary
  `-`, `INCL`/`EXCL`, `ORD`, and `SYSTEM.VAL` like any set.
- **A `SET` is included in a `SYSTEM.SET64`, not the reverse**: it is assigned,
  passed by value, returned and compared by widening with zeros; a mixed
  operation is done at 64 bits. `-x` of a `SET` is its 32-bit complement, so
  `a := -{}` for a `SET64` `a` has 32 elements, not 64.
- **A constant set has the narrowest set type its value fits** (voc types a
  constant by the bytes it needs, as it does for integers): `{}`, `{0, 31}` and
  `{40..30}` are `SET`s, `{0, 32}` and `{0..63}` are `SET64`s, and a computed
  one (`{2, 40} * {2, 31}`, `-{2, 31}`) is typed by what it comes out as. A
  constructor with a *variable* element is a `SET`, or a `SET64` if it has a
  constant element above 31: `{n, 40}` is a `SET64`, `{n}` a `SET`, and a
  variable element that is 32 or more is not detected (`{n}` with `n = 40` is
  a shift past the set's 32 bits, undefined - build it with `INCL` on a
  `SET64`). A constant element outside 0..63 is a compile-time error, and
  `INCL`/`EXCL` reject a constant one outside their own variable's range
  (`INCL(s, 63)` for a `SET`). `ORD` of a set is poc's own extension - the
  report defines `ORD` only for `CHAR`, and voc rejects it for any set (err
  111), which `-strict` does too; `ORD` of a `SET` is an `INTEGER`, of a
  `SET64` a `HUGEINT`.
- **Where poc differs from voc**: voc types a constant *range* `{35..37}` as a
  `SET32` and loses the bits (its `a + {35..37}` on a `SET64` is wrong); poc
  types it by its value. Both are checked in `semantic-set64` and
  `llvm-set64`, which run under `-O2` and `-OC` with the same output.
- **`.sym` files** name the type `SYSTEM.SET64` and write `IMPORT SYSTEM`;
  a constant set is written as its elements, so an importer types it again by
  value (`llvm-set64-import`).

## Pointers, `NEW` and the runtime (implemented, Phase 9 step 5)

Points where `Oberon2.pdf` is silent and poc made a choice (`PLAN.md` step 5
has the full account; all probed against real voc 2026-09-19):

- **NIL handling**: every dereference (`p^`, and the implied one in `p.f`
  and `p[i]`) is NIL-checked and traps ("NIL pointer dereference", exit
  status 4), like voc's default `-p`. So are `NIL IS T`, the type guard
  `NIL(T)` and a NIL `WITH` variable - all three take the same trap, where
  voc says "NIL access" (Halt(-10)); the report is silent on them, and
  poc matches voc's behavior. A failed guard exits 5 and a `WITH` with no
  matching branch and no `ELSE` exits 6. A `NEW` the heap cannot satisfy
  is **not** a trap by default: the pointer is left NIL, as in voc, and the
  next dereference traps. **`poc -trap-heap-exhausted`** (Phase 11 A13, user
  2026-09-25) makes it one instead: `NEW`, `NEW(p, n, ...)` and `SYSTEM.NEW`
  then stop the program with "heap exhausted: NEW cannot allocate the block",
  exit status 11 - when there is no room even after a collection, or a single
  block is larger than the heap takes (`llvm-heap-exhausted`). The switch is
  off by default; without it the IR is unchanged. voc has no such switch. Only the *behavior* matches voc's; the exit statuses
  are poc's own numbering (voc's Halt codes come out as 246 for NIL, 251
  for a failed guard, 249 for `WITH`).
- **`&` and `OR` always short-circuit** (Appendix A requires it; poc kept
  them eager through Phase 8 while nothing could observe the difference,
  and there is no eager path any more).
- **`NEW` needs the runtime on the import path**: no module imports
  `GarbageCollectedHeap`/`ModuleTable` for it - `poc` adds both to the
  program itself whenever any module calls `NEW`, finding them like any
  imported module (`POC_IMPORT_PATH=<repo>/rtl/llvm` or `-import-path`).
  There is no built-in default directory; a missing runtime is an error
  message naming the module.
- **Finalization** (Phase 12 step 5c, 2026-10-02, from voc's `Heap`):
  `GarbageCollectedHeap.RegisterFinalizer(obj, finalize)`, with `finalize`
  a `PROCEDURE (obj: SYSTEM.PTR)`, has `finalize(obj)` called once, after
  the collection that finds `obj` unreachable; what `obj` points to is
  still there for it, and it may store `obj` somewhere reachable again.
  When the program ends - returning from its main module's body, `HALT`,
  `ASSERT`, any trap, `Platform.Exit` - every object still registered is
  finalized, newest first, reachable or not (decided with the user),
  through the C library's `atexit`; after a trap, its message comes
  first. voc runs `Heap.FINALL` at the same points but `Platform.Exit`,
  and before a trap's message. Killed by a signal (`SIGFPE`), a program
  finalizes nothing, under either. `FinalizeAll` is voc's `FINALL`.
  Fixture `llvm-gc-finalize`.
- Pointer variables start NIL, locals included. Since 2026-09-26 (Phase 11
  D16) **every local starts at zero**, not only pointers and procedure
  values: with clang `-O2` the default, a read of a never-assigned local
  would be undefined behavior to LLVM. So all variables - globals, locals
  and heap blocks - start zeroed (0, 0.0, FALSE, 0X, {}, NIL, and records
  and arrays of those).
- Procedure values are Phase 9 step 8's - see "Procedure values, `ASH`,
  `MAX` and `MIN`" below. (`NEW(p, n0, ...)` and pointers to open arrays
  are Phase 9 step 7's.)

## Type-bound procedures and `VAR` record parameters (implemented, Phase 9 step 6)

`PLAN.md` step 6 has the full account; all probed against real voc
2026-09-19. What a program can observe:

- **Dispatch** follows the receiver's *dynamic* type: `v.P(...)` calls the
  procedure bound to what `v` really is, `v.P^(...)` the one bound to the
  base of `v`'s static type. A NIL pointer receiver is a NIL-dereference
  trap (exit 4, "NIL access" in voc), before the procedure starts.
- **`VAR` parameters of record type carry their actual's type** (voc does
  too): a hidden second argument, the actual's type descriptor, follows
  each such parameter - part of the calling convention of every Oberon
  procedure that has one (a call through a procedure value included),
  but not of an external `["C"]` one, which gets the bare address. That is
  what lets `IS`, a guard `v(T)` and `WITH` apply to "a variable parameter
  of record type" (§8.1), which the front end now accepts. Like voc, only
  the parameter's own name qualifies: a plain record variable or a value
  parameter is rejected, and so is a guard of a guard (`x(T)(U)`) or a test
  on a guard (`x(T) IS U`); inside a `WITH` branch the narrowed parameter
  may be guarded and tested again, and `v(T)` may be passed on as a `VAR`
  argument.
- **Two places voc itself falls short**, so poc follows the report: a value
  record parameter accepts an extension of its type (voc's generated C does
  not compile), and a bound procedure of a record written inline under a
  `POINTER TO` can be called (voc gives that record no descriptor and traps
  "NIL access").

## Open arrays (implemented, Phase 9 step 7)

`PLAN.md` step 7 has the full account; all probed against real voc
2026-09-19. An open array - `ARRAY OF T`, or several dimensions
`ARRAY OF ARRAY OF T` - has lengths only known at run time, carried as a
*dope vector* of word-sized integers (as wide as a pointer on the target,
like voc's), outermost dimension first:

- **A formal parameter** (`VAR` or value) is the address of the first
  element, then one hidden length per open dimension - part of every Oberon
  procedure's calling convention, like a `VAR` record parameter's tag, but
  not of an external `["C"]` one, which gets the bare address. A *value*
  parameter is copied into the callee's frame on entry (voc does the same),
  so assigning to it never reaches the caller's array.
- **What may be passed** is what Appendix A calls array compatible: any
  array whose element types are compatible - a fixed array, an open array
  parameter of the caller's own (forwarding), what a pointer to an open
  array points at, a row or element of a larger array - not only the
  identical type, which the checker used to demand of a `VAR` parameter
  (it now matches voc). Fixed element types must still be the *same named
  type*: an anonymous `ARRAY 3 OF INTEGER` inside the formal is not the
  one inside the actual (voc rejects that too). A string literal or named
  `STRING` constant may be passed to a value `ARRAY OF CHAR`; `LEN` of it
  counts the terminating `0X` (`LEN("abc") = 4`), as in voc.
- **Indexing** checks the index against the run-time length (a negative
  index too) and traps like a fixed array's, exit 2; `LEN(a, n)` reads the
  length. `LEN` now has type `LONGINT`, as the checker always said (the
  code generator had typed it `INTEGER`, wrapping a length above 32767).
  `COPY`, string comparison and `NEW` accept open `ARRAY OF CHAR`s too.
- **A pointer to an open array** points at a block that starts with the
  lengths, one word each, then the elements from a fixed offset on (voc's
  own layout, `SYSTEM_NEWARR`); `p[i]`, `p[i, j]` and `p^` work through it
  and a NIL `p` is the usual NIL trap.
- **`NEW(p, n0, ..., nk-1)`** allocates it, one length per open dimension.
  Like voc a length that is not positive - zero included, though the report
  says nothing - traps, exit 7 ("Too many, or negative number of, elements
  in dynamic array", voc's Halt(-20)); so does a size that overflows, which
  voc silently wraps. A heap that cannot supply the block is not a trap:
  the pointer is NIL, as for a record. voc rejects a *constant*
  length <= 0 at compile time ("illegal value of constant"), and so does poc
  since Phase 11 ("constant length of NEW must be positive"; `SYSTEM.NEW(v, n)`
  with a constant `n <= 0` too, which voc lets by); a length that is not
  constant traps at run time.
- **Collector**: the block is tagged with the array descriptor of the
  innermost element type, like a fixed array of pointers (see
  `llvm-open-array-new`, which fails without it).
- **Any number of open dimensions** (Phase 11 A17, 2026-09-25; at most 8
  before, a compile error where the ninth was written): the backend keeps an
  open array's lengths in a list (`LLVMCodeGenerator.DopeVector`), not a
  fixed vector of eight, and builds a call's argument text in a buffer that
  grows (`GrowingText`), not in 800 characters. 400 dimensions were
  probed; `llvm-open-array-many-dimensions` runs 9, 20 and 64 against voc.
  voc has no limit on the type either (`OPP.Mod` counts open dimensions
  without a check); its 127 (`OPB.Mod`) is only the largest dimension
  `LEN(a, n)` can name, where poc checks `n` against the type.
- The copy of a value parameter is made even when the procedure only reads
  it: `memmove` of the actual's whole length (a 4096-character buffer
  passed for a short string copies 4096 bytes). Skipping it was considered
  and dropped (Phase 11 A17): all copying together (`memmove`, `memcpy`)
  was 0.17% of the instructions of poc compiling itself, which passes 212
  value open-array parameters, against 91% in the collector (A15).
  (A procedure *type* with open-array parameters works: a call through a
  value passes the lengths like any other call - step 8.)

## Procedure values, `ASH`, `MAX` and `MIN` (implemented, Phase 9 step 8)

`PLAN.md` step 8 has the full account; all probed against real voc
2026-09-19. What a program can observe:

- **A procedure name is a value** (`f := Add`, `Apply(Add, 1, 2)`, `RETURN
  Add`, a record field or array element of procedure type) and a value can
  be called (`f(1, 2)`, `t.op(x)`, `tbl[i](x)`, a bare `act` for a proper
  procedure with no parameters). Oberon2.pdf 6.5 forbids a predeclared,
  type-bound or nested (local to another procedure) procedure as a value,
  and poc and voc both reject them; poc also rejects an *external* `["C"]`
  procedure, whose C calling convention differs from the Oberon one a
  procedure value is always called with. A procedure's *name* is not an
  operand of `=`/`#` (`f = Add` is an error, as in voc: compare `f = g`,
  `f = NIL`); a procedure-typed value is.
- **Calling a NIL procedure value** is the NIL trap (exit 4; "NIL access" in
  voc), for a variable, a field (through a NIL pointer too), an element or
  a parameter. A procedure variable that is local (or inside a local record
  or array) starts NIL, like a local pointer - poc's guarantee; in voc it is
  stack garbage.
- **Calling convention**: a value is called with the arguments its
  *type's* parameter list lays out, hidden ones included (a `VAR` record's
  type tag, an open array's lengths) - the same as a direct call of any
  procedure matching the type.
- **`ASH(x, n)`** shifts `x` left by `n`, or right (flooring) for negative
  `n`, and has the wider of `LONGINT` and `x`'s type (so `HUGEINT` keeps
  its 64 bits; voc's own rule). A count of the result type's width or more
  leaves 0 (the sign, for a right shift); voc agrees to 63 and is
  undefined beyond. voc computes in 64 bits, so an `ASH` that overflows
  `LONGINT` and is compared *without* first being stored disagrees with poc.
- **`MAX(T)`/`MIN(T)`** as run-time expressions are the same constants a
  `CONST` folds to, plus `REAL`/`LONGREAL`: IEEE 754's largest finite value
  and its negation (3.4028234663852886D38 and 1.7976931348623157D308). voc's
  `MAX(LONGREAL)` is deliberately a little low, 1.79769296342094D308 (its
  own `OPM.Mod` says so); poc gives the true one. The `CONST` form folds
  to the same values (Phase 9 step 10; see "Constant expressions" below).
- `ASSERT` is decided and implemented since 2026-09-25; see "ASSERT" below.

## Constant expressions (implemented, Phase 9 step 10)

`PLAN.md` step 10 has the full account; all probed against real voc
2026-09-19, under both size models. What a program can observe:

- **A constant integer expression has the minimal type its value fits**, not
  the wider of its operands' types (Oberon2.pdf 5 says so of "an integer
  constant"; voc re-types after every folded operation). `2 * 100 + 2 * 10`
  is the INTEGER 220 (it used to wrap at SHORTINT width), `MAX(SHORTINT) + 1`
  an INTEGER, `-128` a SHORTINT though `128` is an INTEGER, `100000 * 100000`
  a HUGEINT. The same rule applies in a `CONST` declaration and in an
  ordinary expression (`s := 127 + 1` is rejected for a SHORTINT `s`), and
  the bounds follow `-O2`/`-OC`. A real, BOOLEAN or SET constant expression,
  and a relation between constants, is not folded outside a `CONST`; nothing
  observable depends on it.
- **Folding is done in 64 bits and is an error only past HUGEINT**: "constant
  sum/difference/product/negation/quotient too large for HUGEINT" (voc's
  errors 203-207), and "division by zero" for a constant `DIV`/`MOD`. The
  error is reported at compile time in a statement as well as in a `CONST`.
  `DIV`/`MOD` of constants floor. Integer constants compare exactly.
- **`ASH(x, n)` of constants folds**: a count outside -62..62, or a left
  shift whose result does not fit HUGEINT, is an error (voc's error 208,
  same boundaries). The result is at least a LONGINT, wider if `x` or the
  value needs it - voc keeps LONGINT and silently truncates (`l := ASH(1, 40)`
  stores 0 under `-O2`), poc types it HUGEINT, making that assignment a
  compile error - and, like voc, is not shrunk afterwards: `ASH(1, 3)` is a
  LONGINT.
- **`LEN` of a dimension of fixed length is a constant** (decided with the
  user 2026-10-02, as voc; found by voc's `oocLRealConv`): `LEN(a)` and
  `LEN(a, n)` of an array that is not open there, through any selectors
  (`LEN(r.f)`, `LEN(p^)`), are "predeclared functions that can be evaluated
  at compile time" (Oberon2.pdf 5). Usable in a `CONST` declaration; `LEN`
  of an open dimension there is "not a constant expression: LEN of an open
  array". Unlike every other integer constant it keeps the type the report
  gives `LEN`, `LONGINT`, not the minimal one: so `SHORT(LEN(a))`, the
  common idiom, stays legal and `i * LEN(a)` stays `LONGINT` arithmetic.
  An operation on it is folded as any other, so `LEN(a) - 1` has the
  minimal type of its value, and `FOR i := 0 TO LEN(a) - 1` takes an
  `INTEGER` `i`. And it is assignable wherever its value fits, as a
  constant of the minimal type would be (the user, the same day, as voc):
  `s := LEN(a)` for a `SHORTINT` `s` and 100 elements, and the same for a
  value argument, a `RETURN`, a `FOR` bound and an initializer; 170
  elements under `-O2` stay an error. One difference from voc, whose
  `LEN` constant has the minimal type: poc accepts `SHORT(LEN(a))`
  whenever the value fits `SHORT`'s type, voc not when `LEN(a)` already
  has that type (`SHORT(LEN(a))` of 170 elements under `-O2`: "number too
  large"). Fixtures `llvm-voc-library-fixes`, `semantic-voc-library-fixes`.
- **`NIL` is a constant** (2026-10-02, as voc; `oocChannel`'s `CONST done*
  = NIL`): the report lists it among the factors with `TRUE` and `FALSE`.
  A `NIL` constant is assignable to and comparable with any pointer or
  procedure variable, as `NIL` is, and is written to a `.sym` file.
- **`ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`, `LONG`, `SHORT` and `ODD` of
  constants fold** (Phase 11 step 2, probed against voc under both models: the
  table is `test/conformance/semantic-const-value-functions`, which also lists
  the rows where poc differs). `ORD` takes a `CHAR` or a one-character string
  and is an `INTEGER`; `CHR` takes 0..255; `ABS` of an integer has the minimal
  type its value fits and `ENTIER` is a `LONGINT`; `LONG`/`SHORT` follow the
  checker's types and round a real through single precision; `SHORT` of an
  integer constant is always an error (a constant's type is minimal, so its
  value never fits the shorter one). An argument that does not fit is a
  compile-time error, in a statement as well as in a `CONST`, and in an argument
  where nothing is assigned (`Take(SHORT(100000))`). Until 2026-09-21 that was
  so only where the result was assigned to an integer variable, which `CHR`'s
  `CHAR` never is: `c := CHR(300)` compiled and stored 44 (voc: err 220
  everywhere). `ENTIER` of a
  value beyond the model's `LONGINT` is an error too, and at run time a trap
  (next bullet).
- **`ENTIER` of a value that does not fit a `LONGINT` is a trap** (Phase 11
  step 3, `doc/history/phase-11-inventory.md` A4, decided with the user 2026-09-21):
  x >= 2^31 or < -2^31 under `-O2`, 2^63 under `-OC`, an infinity or a NaN
  stops the program with "ENTIER argument out of range for LONGINT" on stderr,
  exit status 8. The result stays a `LONGINT`, as in the report (which defines
  `ENTIER` only for a value that fits) and in every dialect surveyed - voc, the
  A2 and Oberon V4 compilers, obc, Component Pascal - none of which checks it: voc
  wraps under `-O2` (`ENTIER(10^12)` is -727379968) and gives the hardware's word
  (INT64_MIN) under `-OC`; poc used to answer -2147483648, from an LLVM `fptosi`
  whose result for such a value is poison. A `HUGEINT` result was rejected: it
  helps only `-O2`, and breaks `n := ENTIER(x)` for a `LONGINT` `n`. Checked by
  `llvm-entier-trap` under both models.
- **`MAX`/`MIN` of `REAL` and `LONGREAL` are constants**: IEEE 754's
  largest finite values and their negations, as at run time.
- **A `CASE` label must lie in the range of the selector's type** (Phase 11
  step 3): `CASE b OF 128:` for a `SYSTEM.INT8`, or `CASE s OF 200:` for a
  `SHORTINT` under `-O2` (one byte), is an error, voc's err 60 "wrong type of
  case label" - poc's message is "case label is outside the range of the CASE
  selector's type", and it checks both ends of a range where voc looks only at
  the low end (`CASE b OF 1..300:` compiles under voc). It used to be accepted
  and produced IR clang refused (`semantic-case-label-range`).
- **`.sym` files**: a folded integer is written as its value, so an importer
  re-types it minimally (`ASH(1, 3)` is a SHORTINT there); a real constant
  that is exactly `MAX`/`MIN` of `REAL` or `LONGREAL` is written as
  `MAX(LONGREAL)` and so on. Any other computed real exports too, whatever
  its magnitude (`1.0D300 * 1.5`, subnormals): since Phase 11 step 2
  `ConstantEvaluator.ParseReal` is correctly rounded (`DecimalToDouble`, exact
  big-integer arithmetic), and the `.sym` text is the shortest digits, at most
  17, that read back to the very value (`module-interface-extreme-reals`).

## Overflow, division and reals (decided, Phase 11 C5)

`Oberon2.pdf` says nothing about arithmetic that leaves a type's range, so
this is poc's own promise, decided with the user 2026-09-21 after a survey of
other Oberons (`doc/research/overflow-survey.md` has the sources and the probes; every
surveyed dialect that has a default leaves integer overflow unchecked, ETH's
OP2 family defaulted its `V` pragma off, and no dialect traps underflow).
What a program can observe, the same under `-O2` and `-OC` at each type's own
width, and the same as voc's (`llvm-overflow-wrap` runs one source under voc
and poc, both models):

- **Integer `+ - *`, unary `-`, `ABS`, `INC` and `DEC` that leave the range of
  their type wrap around** (two's complement, at the type's width - `MAX(T)+1`
  is `MIN(T)`, `-MIN(T)` and `ABS(MIN(T))` are `MIN(T)`), and nothing traps.
  This is a promise, not luck: poc emits plain LLVM `add`/`sub`/`mul` (no
  `nsw`), which wrap at any optimization level, where voc's C only happens to.
  An opt-in overflow trap is not offered; it waits for Phase 12 step 1's
  safety-check triage, and for Phase 15 (the VAX's `IV` bit).
- **`DIV` and `MOD` floor for every non-zero divisor**, negative ones included
  (`7 DIV -2` is -4, `7 MOD -2` is -1). A zero divisor and `MIN(T) DIV -1` end
  the program with the hardware's signal (`SIGFPE`, status 136), no message,
  on purpose (C6) - **on x86 only**: LLVM's `sdiv`/`srem` by zero is undefined
  and poc adds no check, so where the divide instruction does not fault (ARM:
  FreeBSD arm64 was probed 2026-09-21) `7 DIV 0` is 0, `7 MOD 0` is 7 and
  `MIN(LONGINT) DIV -1` is `MIN(LONGINT)`, silently. Where poc differs from
  voc: `0 DIV 0` is a `SIGFPE` here, 0 in voc (its `SYSTEM_DIV` returns early
  for a zero dividend), and at `-O2` voc's `MIN(LONGINT) DIV -1` is 2147483648
  (computed wider). A program must not depend on either; "What traps, and what
  does not" below has the whole list.
- **Real arithmetic is IEEE 754 and silent**: overflow and a division by zero
  give an infinity, `0.0/0.0` a NaN, underflow a zero or a denormal, `SHORT`
  of a `LONGREAL` too large for a `REAL` an infinity; no trap. (The VAX backend
  cannot promise this - VAX floats have no infinity or NaN; Phase 15 decides.)
  **On 32-bit x86, only at `-opt 0`** (its default there; Phase 11 D13,
  2026-09-26): LLVM computes reals on the x87 there (clang's default CPU for
  the i386 BSDs has no SSE2, and poc must run on a Pentium II), whose
  registers hold 80 bits. At `-O0` every result is stored, and so rounded to
  its type; an optimized build keeps intermediate results in the registers,
  wider in precision and exponent, so a result can differ in its last bits and
  an underflow or overflow can be missed (on OpenBSD i386 `1.0D40` printed a
  different last digit and `MathL.exp(-800)` reported no underflow). Linux
  i686, whose default CPU has SSE2, is not affected.
- **`ENTIER` is the one exception, on purpose: a value that does not fit a
  `LONGINT` (or a NaN or infinity) traps** - "ENTIER argument out of range for
  LONGINT", exit status 8 (see "Constant expressions" above). It is not
  arithmetic that has a right answer: a wrapped sum is the correct result
  modulo 2^n, and programs use that deliberately (hashes, random number
  generators), but no value is right for `ENTIER(1E30)`, the report defines it
  only for a value that fits, and voc's own answer differs between `-O2` and
  `-OC`. So nothing legitimate is lost, and a silent value would hide what is
  almost always a bug. Reconsidered 2026-09-21 once the rule above was settled
  (poc's other arithmetic never traps, so `ENTIER` is the odd one out, and
  saturating would be the consistent choice); the user kept the trap.
  Loosening it later, to saturation, could never break a working program;
  tightening a silent value later could.
- **`SHORT`, `CHR` and `SET` elements out of range are unchecked**: `SHORT`
  and `CHR` truncate (`CHR(300)` is `","`), `INCL(s, 40)` on a 32-bit `SET`
  shifts past its width. voc's `-r` would halt on the first two; so does
  `poc -range-checks` (Phase 12 step 1, trap 14).

## Array assignment (decided and implemented, Phase 11 A21)

`doc/research/array-assignment-survey.md` has the sources and the probes (voc, OfrontPlus,
A2, obc, and the Oberon-2, Oberon-07, Active Oberon, Component Pascal and Oberon+
definitions). What a program can observe:

- **Rule 6 is unchanged**: `v := "abc"` needs `m < n`, so a string that exactly
  fills the array or is longer is a compile-time error (voc's err 114). Every
  surveyed dialect agrees, and `COPY` is the tool for truncating.
- **An open array is never a target**, and never assignable to another open
  array, `d := s` for two open-array parameters included (`d, s: ARRAY OF
  CHAR`), nor a row `d[i] := s[i]` of an open array of arrays, nor `p^ := q^`
  through a pointer to an open array. Appendix A's "same type" excludes open
  arrays (voc: err 113). poc used to accept `d := s` and then emit IR clang
  refused, because two open arrays declared together share one `ArrayType`.
- **voc's array rule is adopted, beyond `Oberon2.pdf`** (user, 2026-09-21; the
  report has nothing like it): `v := e` where `v` is a *fixed* array and `e` an
  array with the **same element type** (the same `Type`; two anonymous
  `ARRAY 3 OF INTEGER` are the same element type only where the element is
  `INTEGER`, never as a nested anonymous array) that is either a **fixed array
  no longer than `v`** or an **open array**. All of `e` is copied, by size
  (`memmove`) and **whatever it holds** - a `0X` in the middle of a character
  array makes no difference - and what follows it in `v` is left as it was.
  It works for every element type, `CHAR` included, so `fileName := name` (open
  `ARRAY OF CHAR` into a fixed one) is accepted, as are `s1 := s2` for two
  separately declared arrays of equal length (voc treats those as one type;
  poc, per the report, as two, and this rule then copies) and `big := small`.
  Rows and elements of arrays and record fields are targets and sources like
  any variable. Only an *assignment statement* takes it: a value parameter of
  fixed array type still needs its own type, a longer array is still an error,
  and so is another element type (`ARRAY OF LONGINT` into `ARRAY OF INTEGER`).
- **An open source longer than the fixed target stops the program** ("open
  array assigned to an array too short for it", exit status 9), by *length*
  alone: an 8-element buffer holding the two-character string `"ab"` cannot be
  assigned to a 4-element array, as in voc (which reports an index out of
  range, Halt(-2)). Use `COPY` to take what fits.
- **Not done, on purpose**: the terminator-based rule of Component Pascal and
  Oberon+ (copy up to the source's `0X`, halt if it does not fit), which would
  accept the buffer above; an open array as a target (Active Oberon and Oberon+
  accept a string constant there); assignment of a string constant to an open
  array. The survey (section 6) has the reasons. `COPY` is unchanged.
- poc's own source stays inside `Oberon2.pdf`'s rules and does not use it;
  `-strict` rejects it. Checked against voc under both
  size models by `llvm-array-assign`; `llvm-array-assign-trap` (both models)
  covers the trap; `semantic-reject-array-assign` and
  `semantic-reject-open-array-assign` the errors.

## FOR final value (decided and implemented, Phase 11 D10, 2026-09-25)

A restriction, not an extension. `Oberon2.pdf` §9.8 defines
`FOR v := low TO high BY step` as `v := low; temp := high` and a `WHILE` loop
on `v <= temp` (or `>=`), and asks only that `high` be *expression compatible*
("comparable") with `v`. So `high` may be of a wider type than `v`, even a real
type. (The 1993 report and the OOP book's Appendix A say instead that "temp has
the same type as v".) What a program can observe:

- **`high` must be assignment compatible with `v`**, as `low` already is:
  "FOR final value is not assignment compatible with the control variable".
  This is voc's rule (`OPP.Mod`: a non-constant `high` is assigned to a hidden
  variable of `v`'s type, a constant one must be an integer no wider than `v`;
  err 113). With `i: SHORTINT` and `n: INTEGER`, `FOR i := 0 TO n`,
  `FOR i := 0 TO 300` (under `-O2`) and `FOR k := 0 TO r` (`r: REAL`) are
  errors.
- **Why**: under the report's rule, a bound `v` cannot reach loops forever,
  since `v` wraps on overflow ("Overflow, division and reals"). Before this,
  poc accepted any numeric `high` and then converted it to `v`'s type, which
  broke both ways: an `INTEGER` 300 was truncated to the `SHORTINT` 44 (45
  iterations, the result of neither rule), and a `REAL` produced invalid IR,
  which clang rejected.
- The order of evaluation is the report's: `low` is stored into `v` before
  `high` is evaluated, once. voc evaluates `high` first.
- `-strict` does not affect this, since it only removes things. Checked by
  `semantic-reject-for-final-value`, whose three rejected lines are exactly
  the ones voc rejects.
- **A loop ends before a step that would pass `temp`** (decided with the
  user 2026-10-08, with the unsigned types, "Unsigned integer types"
  below; not yet implemented). After the body, the loop exits when the
  distance left, `temp - v` counting up or `v - temp` counting down, is
  less than the step's size, and only otherwise adds the step. The
  distance is computed modulo 2^n at `v`'s width and compared unsigned,
  which is exact, since `v` has not passed `temp`. Wherever the report's
  loop ends, this one runs the same iterations and leaves `v` the same,
  except that `v` is not stepped past `temp` after the last one. Where the
  report's loop would wrap and never end - `FOR i := 0 TO MAX(INTEGER)`,
  or a `SYSTEM.CARDn` counted down to 0 - it ends after `temp`'s
  iteration. A program that reads `v` after the loop sees the last value
  it had in the body, not one step beyond; the report leaves `v`'s value
  after the loop undefined only implicitly, and voc steps past `temp`.

## Declarations after procedures (decided and implemented, Phase 11 A22, 2026-09-25)

`Oberon2.pdf` §10 already lets `CONST`, `TYPE` and `VAR` sections repeat and
come in any order (`DeclarationSequence = {CONST ... | TYPE ... | VAR ...}
{ProcedureDeclaration ";" | ForwardDeclaration ";"}`), but only before the
first procedure. poc also lets them follow procedures, at module level and
inside a procedure, so constants, types and variables can be declared next
to the procedures that use them. Active Oberon and Oberon+ allow the same;
voc, Component Pascal and Oberon-07 do not. What a program can observe:

- **Declare-before-use is unchanged.** A procedure's body sees only what is
  declared above it, so a `VAR` declared after `P` is undeclared inside `P`
  (poc checks each body before anything that follows it). The module body
  sees everything. A procedure named later still needs `PROCEDURE ^`.
- **A declaration after a procedure may not hide a name visible from an
  enclosing scope**: "a declaration after a procedure cannot reuse a name
  visible from an enclosing scope". Inside `Outer`, `VAR i` after a nested
  procedure is an error when a global `i` exists, and so is a module-level
  `VAR LEN` after a procedure. The report's scope rule would let the nested
  procedure's `i` mean the global one and every later use in `Outer` mean
  the local one; forbidding it means a name never changes meaning partway
  through a block, and the backend, which looks names up in the finished
  scopes, always finds what the checker found.
- **A `POINTER TO` base must be declared before the next procedure**: "a
  POINTER TO base type must be declared before the next procedure". Scope
  rule 3's forward reference still works within one run of declarations.
- **The interface is unaffected**: `-show-interface` and the `.sym` file
  list a module's exports grouped as the report orders them, whatever the
  source order, and an importer uses them as usual.
- **`-strict`** reports each `CONST`, `TYPE` or `VAR` section that follows a
  procedure of its block: "a CONST, TYPE or VAR section after a procedure is
  not in the Oberon-2 report (-strict)". poc's own source does not use it
  (voc, which builds Stage 0, rejects it).
- Fixtures: `llvm-declarations-after-procedures` (both size models, with an
  imported module whose exports follow a procedure),
  `semantic-reject-declarations-after-procedures`,
  `semantic-strict-declarations-after-procedures`.

## Variable initializers (decided and implemented, Phase 11 A23, 2026-09-26)

A variable declaration may end with an initializer:

```oberon
VAR
  count: INTEGER := 0;
  a, b, c: INTEGER := Next();
  name: ARRAY 16 OF CHAR := "none";
```

`Oberon2.pdf` has `VariableDeclaration = IdentList ":" Type`; the form is
Modula-3's, and among Oberons only Active Oberon has initializers (constants
only, written after each name). `doc/research/initializers-and-literals-survey.md` has
the survey; decided with the user 2026-09-26. The rules:

- **Each variable of the list gets its own evaluation of the expression**, so
  `a, b, c: INTEGER := Next()` calls `Next` three times, in the order of the
  names.
- The initializer is **an assignment `v := e`** with every rule of one
  (assignment compatibility, strings into `ARRAY OF CHAR`, the array
  assignment rule above), made **before the body**: a local's on every entry
  to its procedure, a global's before the module body, all in declaration
  order. Any expression is allowed, not only a constant.
- **Declare-before-use holds**: the expression can use only names declared
  before its `:=` (the variables of its own list included - they already
  hold 0). A name of the same scope declared later is an error, "`x` is
  declared after this variable; its initializer can use only what is
  declared before it" - also when it would hide an outer name the
  initializer meant.
- An error in the expression is reported once for the whole list.
- Variables only, not parameters; a record field's is the next section's.
- `-strict` rejects it ("a variable initializer is not in the Oberon-2
  report"), and voc cannot compile it, so poc's own source does not use it.

How: the parser makes one `AssignStatementNode` per name - parsing the
expression again for each, so each has its own copy - and puts them at the
front of the body (`Parser.ParseInitializers`, `WithInitializers`); the
checker checks them with the declare-before-use limit
(`SemanticActions.CheckInitializer`, `SymbolTable.limitScope`), and the
backend sees ordinary assignments; the copies share their string literals'
globals (`CollectStringConstantsSeq` walks only the first). Fixtures
`llvm-var-initializers`, `semantic-reject-var-initializers`,
`semantic-strict-var-initializers`.

## Record field initializers (decided and implemented, Phase 11 D17, 2026-09-26)

A record's field list may end with an initializer, the default of its fields:

```oberon
TYPE
  Point* = RECORD x*, y*: INTEGER := 1; tag: CHAR := "p" END;
  Named* = RECORD (Point) name*: ARRAY 8 OF CHAR := "none"; serial*: INTEGER := Next() END;
```

`Oberon2.pdf` has `FieldList = [IdentList ":" Type]`; of the Oberons only Active
Oberon has field initializers, constants only (`doc/research/initializers-and-literals-
survey.md`). Decided with the user 2026-09-26: any expression, and an
initialization procedure per record type. The rules:

- **Every record of the type gets its fields' defaults when it is made**: a
  variable, global or local, a `NEW` (a pointer to a record, or to a fixed or
  open array of them - every element), and a record or array of records inside
  one of those, at any depth. Not a record that is copied (assignment, a value
  parameter), and not `SYSTEM.NEW`'s untyped block.
- A default is **an assignment `field := e`** with every rule of one, made after
  the record is zeroed: first the base type's defaults, then the record's own
  fields in declaration order - each field with an initializer assigned it,
  each field of a record type that has defaults initialized in turn. As for a
  variable, **each field of the list gets its own evaluation** (`e, f: INTEGER
  := Next()` calls `Next` twice), and the expression may be any, not only a
  constant.
- A variable's defaults come **in declaration order with the variable
  initializers**: before its own initializer, after the variables declared
  before it (so `VAR g: T; n: INTEGER := g.x` sees `g.x`'s default). `NEW(p)`
  applies them once `p` holds the block, and not if the heap is exhausted.
- **What the expression can use**: the names declared before its `:=` (declare-
  before-use, as for a variable initializer: "`x` is declared after this field;
  its initializer can use only what is declared before it"), except, for a
  record declared in a procedure, that procedure's variables, parameters and
  procedures - the defaults run outside any procedure's frame (a separate
  procedure, below), and "`v` belongs to a procedure; a field initializer can
  use a procedure's constants and types, not its variables or procedures". Its
  constants and types, and everything at module level, are allowed.
- **Across modules**: a module that imports the type gets its defaults too
  (a variable of it, `NEW`, an extension of it), hidden fields included. The
  `.sym` file says only that a field has one, as `f: T := ..`, which a module
  cannot write itself ("expected an expression"); the values stay in the
  declaring module's code.
- `-strict` rejects it ("a record field initializer is not in the Oberon-2
  report"), and voc cannot compile it.

How: the parser gives each field of the list its own copy of the expression
(`Parser.ParseFieldInitializers`; `.sym` files are parsed with
`InitInterfaceParser`, which accepts `..`); the checker checks each copy as an
assignment once the declarations before it are resolved
(`SemanticActions.CheckFieldInitializer`, with `SymbolTable.limitScope` and
`limitLocals`) and marks each record type that needs initializing
(`Types.RecordTypeDesc.needsInit`, `Types.NeedsInit`). The backend defines one
procedure per such record, `@<Module>.<path>.-init(ptr)` (`EmitInitProcedure`),
and calls it where a record is made (`InitializeAt`, a loop for an array;
`GenerateDeclarationInits` for variables, `GenerateNew`/`GenerateNewOpenArray`).
`<path>` names the record the same way in every module that sees it: a
module-level named record's name, `P.base` for a pointer's anonymous base, and
`T.f`, `A.element` and so on down anonymous types from a module-level `TYPE`
declaration (`SemanticActions.NameInitPaths`); any other record, which no other
module can make, is named `-anonN` by the backend. A program with no field
initializers gets exactly the code it did before. Fixtures
`llvm-field-initializers`, `semantic-reject-field-initializers`,
`semantic-strict-field-initializers`.

## What traps, and what does not (Phase 11 C9)

A list of what happens when a program does something the report leaves
undefined or calls an error, each row probed against the built `poc` on
2026-09-21 (Linux x86_64 under `-O2` and `-OC`, and OpenBSD i386, NetBSD amd64
and FreeBSD arm64 for the rows that depend on the machine) and against voc,
whose behavior is in the last column where it differs. It documents; it is not
a promise beyond what the rows say. Statuses are the process's exit status (a
signal death is 128 + the signal number, as a shell reports it).

**What poc traps.** The program writes the message and a newline to stderr
(until 2026-09-21 the newline was missing, and the shell's prompt landed on the
message's line) and exits with the status; the numbers are poc's own (voc's Halt codes
in the last column are `Halt(n)` printed as "Terminated by Halt(n)", exit 256-n).
No location is reported by default; **`poc -trap-location`** (C7, below) adds
one to every trap in this table. Each status is pinned by a fixture.

| Status | What | Message | voc |
|---|---|---|---|
| 2 | Index out of range: a fixed array, an open array, what a pointer to an open array points at; a negative index too (`llvm-index-range-trap`, `llvm-open-array-traps`) | `index out of range` | Halt(-2), 254 |
| 3 | `CASE` with no matching label and no `ELSE` (`llvm-case-trap`) | `no matching CASE label` | Halt(-4), 252 |
| 4 | NIL dereference: `p^`, `p.f`, `p[i]`, `NIL IS T`, `NIL(T)`, a NIL `WITH` variable, a call of a NIL procedure value, a type-bound call on a NIL receiver (`llvm-pointer-traps`, `llvm-procedure-value-traps`) | `NIL pointer dereference` | Halt(-10), 246 |
| 5 | Failed type guard (`llvm-pointer-traps`) | `type guard failed` | Halt(-5), 251 |
| 6 | `WITH` with no matching branch and no `ELSE` (`llvm-pointer-traps`) | `no matching WITH guard` | Halt(-7), 249 |
| 7 | `NEW(p, n, ...)` or `SYSTEM.NEW(v, n)` with a length that is not positive, or a size that overflows the address space (`llvm-open-array-traps`, `llvm-system-new-trap`) | `Too many, or negative number of, elements in dynamic array` | `NEW`: Halt(-20), 236; `SYSTEM.NEW(v, 0)` is no trap |
| 8 | `ENTIER` of a value that does not fit a `LONGINT`, an infinity or a NaN (`llvm-entier-trap`) | `ENTIER argument out of range for LONGINT` | none: wraps |
| 9 | An open array assigned to a fixed array with fewer elements (`llvm-array-assign-trap`) | `open array assigned to an array too short for it` | Halt(-2), 254 |
| 10 | A failed `ASSERT(x)` or `ASSERT(x, n)` (`llvm-assert`) | `assertion failed`, or `assertion failed (n)` | "Assertion failure." and " ASSERT code n."; exit `n`, 255 for none or 0 |
| 11 | With `-trap-heap-exhausted` only: `NEW`, `NEW(p, n, ...)` or `SYSTEM.NEW` the heap cannot satisfy (`llvm-heap-exhausted`) | `heap exhausted: NEW cannot allocate the block` | no switch: the pointer is NIL |
| 12 | A function procedure that reaches its `END` (Oberon2.pdf 10.1); the location is the `END` (`llvm-return-trap`; Phase 12 step 1, until then a zero was returned) | `function procedure reached its END without RETURN` | Halt(-3), 253 |
| 13 | `v := e` for records where `v`, a `VAR` parameter (a receiver too) or `p^`, has a dynamic type that extends its static type (Oberon2.pdf 9.1; `llvm-record-assign-trap`; Phase 12 step 1, until then the static type's fields were copied) | `record assigned to a variable whose dynamic type extends its static type` | Halt(-6), 250; not under `voc -t` |
| 14 | With `-range-checks` only: `SHORT(x)` of an integer `x` outside the result type, `CHR(x)` of `x` outside 0..255 (`llvm-range-checks`; Phase 12 step 1) | `SHORT argument out of range`, `CHR argument out of range` | `voc -r`: Halt(-8), 248, except `CHR` of a negative value (voc's check compares signed); no switch: truncates |

**The library's own failure.** `Files` stops the program with status 99 when
it meets an error it cannot hand back to the caller - a file that cannot be
created, a failed write or seek, a file name too long - after writing
"`-- <what>: <file>`" on a line of its own to stderr (Phase 11 D12, 2026-09-25;
until then to stdout, as voc's `Files` still does). `-trap-location` does not
apply to it. `llvm-files-fail` pins the message, its stream and the status.

**`-trap-location`** (Phase 11 C7, decided with the user 2026-09-25). With it,
every trap message above starts with where the trap is and ends with the
procedure it is in:

    list.mod:42:15: index out of range (in List.Insert)
    lib/traplib.mod:19:7: assertion failed (20) (in traplib.Get.Check)
    traplocation.mod:36:8: no matching CASE label (in traplocation, module body)

- The file is the module's source as poc opened it: the name on the command
  line for the top module, `<import-path dir>/<name>` for an imported one found
  through the search path, so a trap in `rtl/llvm` names that file. The
  procedure is the one the code is in: `Module.Proc`, `Module.Outer.Inner` for
  a nested one, `Module.Record.Proc` for a type-bound one (named after the
  record it is bound to, as its symbol is), "`Module`, module body" outside any.
- The position is the expression that traps where there is one - the index of
  `a[i]` (on its own line if the expression spans lines), the designator
  dereferenced, the guard, the `ENTIER` call - and the statement for a trap of
  the statement itself: `CASE`, `WITH` (their own line, not that of a branch),
  `NEW`, `SYSTEM.NEW`, `ASSERT`, an array assignment.
- The exit statuses do not change, and nothing else does: `HALT` stays silent,
  a signal death (`SIGFPE`, `SIGSEGV`) has no message. Each trap site has its
  own message string, written into the program, so no formatting happens at
  run time; the program grows by one string per site. Without the switch the
  IR is what it was. The switch goes with `-emit-llvm-ir` or `-build`, and with
  `-trap-heap-exhausted` too (`llvm-trap-location`, both size models).

**What ends the program without a message, or not at all.** Nothing says what
happened; deliberate (C6) where noted.

| What | Result | Notes |
|---|---|---|
| Integer `DIV`/`MOD` by zero, `MIN(T) DIV -1` | `SIGFPE`, status 136, **on x86 only** | LLVM leaves it undefined; on ARM (FreeBSD arm64) `7 DIV 0` is 0, `7 MOD 0` is 7, `MIN(LONGINT) DIV -1` is `MIN(LONGINT)`, no fault. voc: `SIGFPE`, except `0 DIV 0` is 0 and `-O2`'s `MIN(LONGINT) DIV -1` is 2147483648. Not pinned by a fixture (host-dependent). **Left as it is** (user, 2026-09-21): `SIGFPE` on x86, no fault on ARM, documented here and nowhere enforced |
| Unbounded recursion; a frame or a value open-array parameter larger than the stack | `SIGSEGV`, status 139, no message | how much fits is the host's stack limit (`ulimit -s`: 8 MB on Linux, 4 MB on OpenBSD and NetBSD, 1 GB on the FreeBSD VM, where a 400 MB local and a 300 MB value parameter both succeeded); a value open-array parameter is copied into the callee's frame, so each level costs `LEN` bytes. voc: same. `llvm-no-trap-behavior` case 12 |
| `SYSTEM.GET`/`PUT`/`MOVE` at an address that is not mapped | `SIGSEGV`, status 139 | voc's handler turns it into "NIL access" (Halt(-10), 246). `llvm-no-trap-behavior` case 11 |
| `HALT(n)` | exit status `n`, silent (C6) | `n` is a constant in **0..255**, anything else is a compile-time error (as voc's err 218): the status keeps only its low 8 bits on every host poc runs on (C `exit(30000)` is 48, `exit(256)` is 0 - success - and `exit(-1)` is 255, checked on Linux, OpenBSD, NetBSD and FreeBSD 2026-09-21), while Windows keeps 32 (a `DWORD`). The report leaves the meaning of `n` to the system. VMS is different again, see `000-todo.org`. voc prints "Terminated by Halt(n)". `llvm-predeclared-halt`, `llvm-no-trap-behavior` |
| `NEW` the heap cannot satisfy | the pointer is NIL, no message; the next dereference is trap 4 | as in voc, and the default; `-trap-heap-exhausted` makes it trap 11 instead. Which requests "cannot" be satisfied depends on the size model and the machine's limits: `NEW(p, MAX(LONGINT))` of 4-byte elements under `-OC` overflows the address space (trap 7), under `-O2` it asks for 8 GB, which was NIL under a 1.2 GB address-space limit |

**What nothing stops.** The program goes on with a value; the second column is
what that value is.

| What | Result |
|---|---|
| Integer `+ - *`, unary `-`, `ABS`, `INC`, `DEC` out of range | wraps at the type's width (a promise, C5) |
| `x IN s` with `x` outside `0..MAX(SET)` | `FALSE` (`llvm-no-trap-behavior` case 7) |
| `INCL`/`EXCL` with an element outside the set, `{n}` with a variable `n` >= 32 | undefined: the shift wraps at the machine's width (`INCL(s, 33)` set bit 1 on x86), unchecked; constant ones are compile-time errors |
| Real overflow, underflow, `x/0.0`, `0.0/0.0` | infinity, 0, infinity, NaN, silently (C5); `llvm-no-trap-behavior` case 9 |
| `SHORT` or `CHR` of a value that does not fit | truncates (`CHR(300)` is 44), as voc without `-r`; **`poc -range-checks`** makes it trap 14 (Phase 12 step 1, `doc/developer/voc-options.md`) |
| `FOR v := a TO b` when `b` is `MAX` of `v`'s type | never ends: `v` wraps to `MIN` and the loop runs on, as the report's own expansion (`v <= b`) says once overflow is undefined; voc the same (`llvm-no-trap-behavior` case 8) |
| `ASH(x, n)`, `LSH`, `ROT` with a count of the type's width or more | defined and not a trap: `ASH` gives 0 (the sign for a right shift), `LSH` 0, `ROT` counts modulo the width; voc's are C's undefined shifts (`ROT(1, 33)` is 0 there, 2 here) |
| `MOVE(a, b, n)` with `n <= 0` | moves nothing (voc, probed with `n = -4`, copied) (`llvm-no-trap-behavior` case 6) |
| `COPY(x, v)` | copies up to the source's `0X`, at most `LEN(v) - 1` characters, and always terminates `v`; a source without a `0X` is read to its end (`llvm-no-trap-behavior` case 4) |
| `=`, `<`, ... on character arrays with no `0X` | the array's end counts as a `0X`, so two equal unterminated arrays are equal; voc reads past the end. `LEN` is the declared length whatever the contents (`llvm-no-trap-behavior` case 5) |
| A variable never assigned | zero: 0, `FALSE`, `0X`, `{}`, `NIL`, for module variables, locals (zeroed on every entry, since Phase 11 D16, 2026-09-26) and heap blocks alike; until D16 a local that was not a pointer or procedure value held whatever was in the frame (a probe read the 77s a previous call had left), as in voc (`llvm-no-trap-behavior` case 0) |

**Compile time: what is an error before the program runs.** Where the compiler
can see a trap or an undefined result coming, it says so - as voc does, apart
from `SYSTEM.NEW`. Errors: a constant `DIV`/`MOD` by zero, a constant real
division by zero (`1.0/0.0`, in a `CONST` and in a statement, and reported by
`poc -check`), a constant `CHR`, `SHORT`, `ENTIER` or `ASH` argument that does
not fit, a constant `INCL` element out of range, `FOR ... BY 0`, `LEN(a, n)`
past the rank, `HALT` outside 0..255, **a constant index outside a fixed array**
(`a[10]` on 4 elements, `g[1][4]`, through a pointer to a fixed array too), and
**a constant length of `NEW(p, ...)` or a constant size of `SYSTEM.NEW` that is
not positive** (`semantic-reject-constant-traps`). Not errors, because nothing
constant is involved: an index or length held in a variable is a run-time trap
(status 2 and 7), and an open array has no length to compare with. All of this
was found probing C9 and decided with the user on 2026-09-21; poc used to
compile the constant index and `NEW(p, 0)` and trap when they ran, and to
report a constant real `x / 0.0` in a statement only from the code generator
(`poc -check` said "semantic OK", and `-build` printed the error yet still wrote
an executable). A build that meets an error while generating code now writes
neither the `.ll` nor an executable, whatever raised it.

## ASSERT (decided and implemented, 2026-09-25)

`doc/research/assert-survey.md` has the survey (the reports, voc, Ofront, OfrontPlus,
BlackBox, A2, obc, oo2c, OBNC) and the decision. `Oberon2.pdf` has no `ASSERT`;
every other dialect surveyed does. What a program can observe:

- **`ASSERT(x)` and `ASSERT(x, n)`** are predeclared proper procedures: `x` a
  BOOLEAN expression, `n` an integer constant in 0..255, as `HALT`'s argument
  and as in voc (its errs 120, 69 and 218 have poc counterparts). A module may
  declare its own `ASSERT`, which hides the predeclared one.
- **A FALSE condition is a trap**: "assertion failed", or "assertion failed
  (n)" when there is a code, and a newline on stderr, then exit status **10**,
  the code or not (voc exits with `n`, or 255 when there is none or it is 0).
  The condition is always evaluated, so its side effects happen; nothing turns
  assertions off (voc's `-a` waits for Phase 12 step 1).
- **A condition that is a constant FALSE is a compile-time error**, "ASSERT
  condition is always FALSE", as voc's err 99 (Ofront and A2 agree; BlackBox,
  obc and Oberon-07 compilers accept it as an unconditional trap, Oberon-07
  having no `HALT`). So a constant condition is a static check:
  `ASSERT(SIZE(T) = 8)` fails at compile time. Use `HALT` for code that must
  not be reached.
- There is no message-string form. `-strict` rejects `ASSERT`; poc's own
  source does not use it. Checked by `llvm-assert` (both
  size models, the same assertion firing as in voc) and
  `semantic-reject-assert` (the lines voc rejects).

## Nested procedures (implemented, Phase 11 step 8)

`PLAN.md` step 8 and `doc/developer/nested-procedures.md` have the full account; the
front end always accepted them, the LLVM backend used to reject them with an
error (before that it dropped the calls silently). What a program can observe:

- **A procedure may be declared inside another, to any depth, and use the
  variables of every procedure around it**: locals, value and `VAR`
  parameters (a `VAR` record parameter keeps its run-time type, an open array
  its lengths), the receiver of a type-bound procedure, and `FOR` control
  variables. Access is
  by reference: what a nested procedure writes is what the enclosing one reads
  next, a pointer variable of the enclosing procedure stays a collector root
  where it is, and each activation of a recursive procedure has its own
  variables, seen by the nested procedure it called. Names are resolved by
  Oberon's scope rules, so a nested procedure's own declaration of the same
  name hides the enclosing one.
- **A nested procedure is called by name only**, from the procedure that
  declares it or from anything declared inside that, itself included, siblings,
  and the enclosing procedure (recursion); forward declarations (`PROCEDURE ^`)
  work among them for mutual recursion. It is never a procedure value (the
  report forbids it and poc rejects it), never type-bound, and never exported:
  a `.sym` never mentions one. A module-level or type-bound procedure may
  contain nested ones and be exported as usual.
- **How it is done**, visible only in the IR, a debugger or `poc -dump-nested
  <file>` (which prints, for each nested procedure, the enclosing variables it
  needs): a nested procedure becomes a function `@Module.Outer.Inner` (`@Module.
  Type.Method.Inner` inside a type-bound procedure) that takes, after its own
  parameters, one hidden `ptr` per enclosing variable it uses - or reaches
  through the nested procedures it calls - in a fixed order (outermost
  declaring procedure first, then declaration order), each followed by the
  variable's type tag if it is a `VAR` record or its lengths if it is an open
  array. A call passes its own bindings' addresses on. There is no static link
  and no closure: an activation never outlives the one that declared it.
- **`WITH` on a pointer variable follows voc's rule**: a pointer that is
  mentioned, read or written, from a procedure other than the one that
  declares it is never narrowed - a nested procedure of the declaring one, or,
  for a module-level pointer, any procedure (so a `WITH` on a global inside a
  procedure is always an error) - nor is a `VAR` parameter or a qualified
  `M.v`; a `VAR` record parameter or receiver is exempt. "Declares" is by
  identity, so a nested procedure's own same-named variable does not count.
  The error is voc's ("guarded pointer variable may be manipulated by non-local
  operations; use an auxiliary pointer variable"). Until 2026-09-21 poc only
  looked for bare `:=` in nested procedures, missing a `VAR` argument (a
  memory-unsafe program was accepted) and accepting a mere read that voc
  rejects (`semantic-with-leaf-rule`).
- **Limits**: none on open dimensions (the section above); a procedure that uses very many
  enclosing variables has that many hidden parameters, which is legal and
  untested at scale. Nothing else is specific to nested procedures.
- Checked (`llvm-nested-*`, `nested-analysis-*`) on Linux x86_64 under `-O2`
  and `-OC`, as 32-bit x86 executables (`llvm-i686-runtime`), and on the local
  VMs: OpenBSD i386 (both size models), NetBSD amd64 and FreeBSD arm64.

## External procedures

`Oberon2.pdf` defines no mechanism for calling procedures implemented in
another language, only the low-level `SYSTEM` module (Appendix C) for
memory/register access. Peaseblossom needs one anyway, so poc's language
has a deliberate, documented extension for declaring an **external
procedure** — analogous in spirit to how `AGENTS.md` documents voc's own
extensions (its "Reference implementation: Vishap Oberon (voc)"), except this one is
Peaseblossom's own.

- **Simplest case**: calling external C functions on Linux/Unix-like
  targets (including the NetBSD/OpenBSD/FreeBSD portability goal in `AGENTS.md`) —
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
  Phase 8's LLVM/C-interop case, `"VMS"` for Phase 15's VMS Calling
  Standard case — both accepted now; the LLVM backend reports an external
  `["VMS"]` procedure as something it cannot lower rather than calling it
  as C, Phase 11, and the VAX backend lowers `"VMS"` and refuses `"C"`,
  Phase 15 step 5). An optional second string overrides the
  external linkage name, since Peaseblossom's own naming convention (see
  `PLAN.md`'s "Naming convention" — descriptive, often-long identifiers) routinely
  won't match a terse external symbol like `malloc` or `printf`:
  `PROCEDURE ["C", "malloc"] AllocateBytes*(size:
  LONGINT): SYSTEM.ADDRESS;`. Without the second string, the external
  symbol is the procedure's own Oberon identifier verbatim
  (`SymbolTable.ObjectDesc.externalName`). This interacts with the VAX
  backend's 31-character name-mangling requirement (Phase 15, below): an
  external procedure's linkage name is emitted **verbatim, never
  mangled** — it has to match the real external symbol, unlike poc's own
  internally-generated names. Both backends' actual lowering is still
  Phase 8/14 work; Phase 6 only records the linkage info
  (`SymbolTable.ObjectDesc.externalConvention`/`externalName`) for a
  later backend to consume.

## `-strict` (decided and implemented, Phase 11 B2, 2026-09-25)

**`poc -strict`** rejects everything beyond `Oberon2.pdf` in the source of the
module named on the command line, in any command (`-check`, `-emit-interface`,
`-emit-llvm-ir`, `-build`). What that module imports is not checked - an
import's source or `.sym` may use extensions, and a strict module may use what
it exports - since the question is what the strict module's own text says.
Each use is an error, "\<construct\> is not in the Oberon-2 report (-strict)"
(the report meant is `Oberon2.pdf`):

- the predeclared `HUGEINT` and `ASSERT` (a module's own declaration of either
  name is fine), and `SYSTEM`'s names beyond Appendix C: `ADDRESS`,
  `INT8`/`INT16`/`INT32`/`INT64`, `SET32`, `SET64` - wherever written, types,
  `MAX`/`MIN`/`SIZE` arguments and `SYSTEM.VAL` included (`SymbolTable.
  ObjectDesc.isExtension`);
- an external procedure (`PROCEDURE ["C", ...]`);
- voc's array assignment (an array of another type assigned whole);
- an integer constant that needs `HUGEINT` (a literal, or where folding first
  goes past `LONGINT` - so it depends on the size model), and a set constant or
  constructor element above `MAX(SET)`;
- `ORD` of a set;
- comparing a `SYSTEM.PTR` with a pointer of another type;
- a hexadecimal constant above `MAX(HUGEINT)`, taken as a 64-bit pattern
  (since 2026-09-27, "Hexadecimal constants as 64-bit patterns" below).

Not on the list, because they change what a legal program *does*, not which
programs are legal: overflow wrapping, the `ENTIER` trap, `ADR`'s result being
a `SYSTEM.ADDRESS`, `BIT`'s byte meaning; nor poc's restrictions (`HALT` in
0..255). `SYSTEM` itself, as Appendix C has it, is in the report.

**poc's own source is checked with it**: `make check-strict` runs `poc -OC
-strict -check` on every module of `src/`, against the `.sym` files Stage 1
leaves, and `make check` runs it. `rtl/llvm`, the runtime, is exempt (it needs
`SYSTEM.ADDRESS` and external procedures). Its first run found poc's own
constant folder holding a set constant in a `SYSTEM.SET64` (since the `SET64`
work, 2026-09-21), which voc, poc's Stage 0, accepts; `Types.Value` now holds
it as two `SET`s (`setLow`, `setHigh`). Fixtures `semantic-strict` (every item,
rejected with the switch and accepted without) and `semantic-strict-import`
(a strict module importing one that uses extensions).

Found by the survey and fixed for every mode, not only `-strict` (user,
2026-09-25), since the report and voc reject them and poc accepted them by
accident:

- **A guard, `IS` or `WITH` on a pointer names a pointer type**: `p IS E`,
  `p(E)` and `WITH p: E` with `E` a record type are errors ("a guard on a
  pointer must name a pointer type, not a record type"); write `p IS EP` for
  `EP = POINTER TO E`. The report says "T is an extension of the static type
  of v", and all its examples name the pointer type; voc (err 86), Component
  Pascal and A2 agree. poc accepted the record type, and inside the guard `p`
  then had the record type - neither assignable to a pointer nor
  dereferenceable. A `VAR` record parameter is still tested with a record type
  (`semantic-reject-guard-record-for-pointer`).
- **`=` and `#` compare pointers only of related types, and procedure values
  only of one type**, as Appendix A says ("NIL, pointer type T0 or T1", "procedure
  type T, NIL") and voc (err 100): two unrelated pointer types, or two different
  procedure types, are an error. The rule is assignment's, either way round; a
  `SYSTEM.PTR` still compares with any pointer, which `-strict` rejects.

## Read-only parameters (decided and implemented, 2026-10-05)

voc has an extension neither report has: a formal parameter written `x-`
(`PROCEDURE Print(text-: ARRAY OF CHAR)`) is passed **by reference, like a
`VAR` parameter, and cannot be assigned to**. The aim is a `VAR` parameter's
cost without the risk of the procedure changing the caller's variable.
Probed against voc 2026-09-25 (its `OPP.Mod`, `FormalParameters`, makes `x-`
a `VarPar` with visibility `readOnlyPar`; voc's `doc/` does not mention it):

- `x := 1` in the body is err 76, "this variable (field) is read only".
- The actual parameter must be a variable, as for `VAR`: `Print("abc")` and
  `P(g + 1)` are err 122, "actual VAR-parameter is not a variable". So it is
  no substitute for a value `ARRAY OF CHAR` parameter taking a string.
- `VAR x-` is err 246, "read-only parameter '-' cannot be combined with VAR".
- `x*` is a syntax error ("':' missing").

It is the feature the Oakwood Guidelines (October 1995) describe in 5.13,
"Read only VAR Parameters", **and recommend against**: "Discussions with ETH
suggest this is really a compiler code optimisation issue and on this basis it
is recommended that this extension is not implemented." So voc adopted it
contrary to Oakwood's own recommendation. Component Pascal has the same idea
as its `IN` parameter mode: a variable parameter, read-only inside the
procedure, for array and record parameters only (Component Pascal report,
10.1).

**Until 2026-10-05 poc did not have it.** A mark on a formal parameter, `-` or
`*`, was a syntax error, "a formal parameter cannot have an export mark", since
`Oberon2.pdf`'s `FPSection` takes plain identifiers
(`parser-reject-param-export-mark`). Until 2026-09-25 poc parsed the names as
`IdentDef`s and dropped the mark, so `x-` compiled as an ordinary, assignable
value parameter.

**Decided 2026-10-05 (the user): poc adopts it, in a version that also
takes a constant, as an ongoing language enhancement** (`PLAN.md`, "Ongoing
language enhancements"; it was Phase 19's candidate 2 until that day). The need is the runtime's `OutStr`
and `InStr` (`PLAN.md`, "Ongoing library enhancements"): `InStr` reads a
string token by token, and a value `ARRAY OF CHAR` parameter is copied on
every call, while a `VAR` one refuses a string constant. voc's `x-` refuses
a constant as well (err 122 above), so poc's differs from voc's there. The
rules (the user, 2026-10-05):

- **Read-only inside the procedure, checked at compile time**: assigning
  to `x` (or to any part of it) is an error, and so is passing it, or any
  part of it, as the actual of a `VAR` parameter, or calling a type-bound
  procedure with a `VAR` receiver on it (voc does not check the last).
  Passing it on to another read-only or value parameter is allowed, and
  so is writing through a pointer it holds. `VAR x-` is an error, as in
  voc; `x*` is still a syntax error.
- **It takes any expression**: a variable, by reference or by value as
  below; a constant, a string included; or any other expression
  (`P(g + 1)`), evaluated into a temporary that is then passed as a
  variable would be. A program that passes anything but a variable to an
  `x-` parameter compiles with poc but not with voc.
- **How it is passed is the compiler's choice, made from its size**: a
  small one (an integer, `SET`, `HUGEINT`, a real, a `CHAR`, a pointer, a
  small record or array) is passed by value, as a value parameter is; a
  large one by reference, a constant by reference to the constant's own
  storage, so neither is copied. Only the read-only rule makes the choice
  invisible, so it is a matter of cost, not of meaning.
- **Small is at most 16 bytes** (the user, 2026-10-05): two words on a
  64-bit machine, four on a 32-bit one (VAX included). The choice is made
  from the formal parameter's type alone - its size (`MemoryLayout`) for
  the size model and the target being compiled for - so the caller and the
  procedure agree, across modules too, without either seeing the other's
  code. The same type may therefore be passed by value under `-O2` and by
  reference under `-OC` (`RECORD a, b, c, d, e: INTEGER END` is 10 bytes
  and 20), or by value on a 32-bit target and by reference on a 64-bit one
  (a record of three pointers is 12 bytes and 24). The `.sym`
  format records the mark, not the choice. An open array is always passed by
  reference.
- **A program may not rely on which** (the user, 2026-10-05, after Ada's
  rule for parameters whose passing mode the language leaves to the
  compiler, RM 6.2): the choice shows only when the caller's variable
  changes during the call, through a global or a `VAR` parameter that is
  the same variable - passed by reference the procedure sees the change,
  by value it does not. As Ada makes this a bounded error (RM 6.2(12)),
  such a program reads either the old value or the new one, and which may
  differ between machines, size models and poc versions; poc does not
  detect it.

- **`-strict` rejects the mark**, and needs nothing else: a module
  without it cannot declare a read-only parameter, though it may call an
  imported procedure that has one. poc's own source does not use it.

**Implemented 2026-10-05.** `Parser.ParseParamName` keeps the mark as the
name's `exportReadOnly`; `Types.Param.isReadOnly` and
`SymbolTable.Object.isReadOnlyParam` carry it, `ParamListsMatch` compares it,
and `CheckDesignator` makes such a parameter read-only as it does an imported
read-only variable, so the assignment checks and the predeclared procedures'
writable-variable checks apply unchanged. `CheckArguments` now refuses any
read-only variable as a `VAR` argument - which also fixed poc accepting an
imported read-only variable there (voc: err 76) - and a bound call refuses a
read-only record as a `VAR` receiver. A `.sym` file writes `x-`. In the LLVM
backend `ReadOnlyByReference` makes the choice; the procedure binds a
by-reference one, and a read-only open array, to its incoming address without
copying it; the caller passes a variable's or a structured constant's address,
a literal's stack slot, or for a string a private constant global of the
parameter's type. Fixtures: `parser-reject-param-export-mark`,
`semantic-reject-readonly-param`, `semantic-strict-readonly-params`,
`llvm-readonly-params` (the 16-byte boundary, under `-O2` and `-OC`).

## Underscores and dollar signs in identifiers (decided and implemented, Phase 11 A25, 2026-09-26)

`000-todo.org` asked for `_` and `$` in names, for VMS (`SYS$QIO`,
`LIB$GET_VM`, `SS$_NORMAL`). `Oberon2.pdf` has `ident = letter {letter |
digit}`. Surveyed 2026-09-26 in the scanners under
`/usr/local/sw/src/lang/Oberon`:

- **`_` accepted:** BlackBox/Component Pascal (`DevCPS`, anywhere, first
  included, as its report says), Ofront+ (`OfrontOPS`, the same), Oberon+
  (`ObLexer.cpp`, the same), A2's Fox (`FoxScanner`, after the first
  character), oo2c (`OOC/Scanner.Mod`: an option, `enableIdentUnderscore`,
  that its compiler always sets; not first), OBNC (`Oberon.l`: a single `_`
  between letters or digits only).
- **`_` rejected:** voc (`OPS.Mod`), the original Ofront, the ETH Oberon-2
  compiler (`Oberon.OPS.Mod` in AOS), obc (`lexer.mll`).
- **`$`:** in no dialect's identifiers; Component Pascal and Oberon+ use it
  as an operator or to start a hex string.

**poc accepts both, anywhere a letter may be, first included** (decided
with the user 2026-09-26, Phase 11 A25). `-strict` rejects them, once for
each name that has one: `"$" in an identifier is not in the Oberon-2 report
(-strict)`.

A first decision the same day took neither, on the grounds that a VMS
routine is an external procedure whose linkage-name string carries its real
name (`PROCEDURE ["VMS", "SYS$QIO"] QueueIO(...)`, "External procedures"
above). That holds for procedures only. Most of the system's names are
values and field names - status codes (`SS$_NORMAL`), function codes
(`IO$_READVBLK`), control-block and descriptor fields (`DSC$W_LENGTH`) -
defined in STARLET, which is written in SDL. VMS gives each language its own
rendering of those definitions (VAX C's `#include <ssdef.h>`), and for
Oberon-2 that is a module of constants and types, whose names have to be
the system's for its documentation to apply. So the decision was reopened
and reversed.

What VMS itself allows (the manuals of the 5.x releases): VAX MACRO takes
letters, digits, `_`, `$` and `.` in a symbol, and forbids only a digit
first (VAX MACRO and Instruction Set Reference Manual, VMS 5.0, 3.3.2); by
DIGITAL's convention, `$` marks names DIGITAL defined. VAX C counts `_` and
`$` as letters, first included, though it reserves a leading `_` for its own
names (Guide to VAX C 3.0, 5.5). The VAX object language stores every
name as a counted ASCII string of at most 31 characters and restricts the
characters no further (VMS 5.0 Linker Utility Manual, chapter 7); the linker
asks for quotation marks, in an options file, only around a name with
characters other than letters, digits, `$` and `_` (the same manual, 5.2),
and allows any printable character in a program section's name, though it
discourages `$` there, as DIGITAL's (6.2.1.1). The VAX Procedure Calling and
Condition Handling Standard (Introduction to VMS 5.4 System Routines,
chapter 2) says nothing about the characters of a name; its own symbols
(`DSC$K_DTYPE_T`) use both. So a name starting with `$` or `_` is valid
everywhere down to the object file.

Nothing in Oberon-2's syntax uses either character, so the grammar stays
unambiguous. LLVM names allow both. The names poc's backend makes up for
itself (anonymous records, record initialization procedures, struct types)
contain a `-`, which no identifier can, so a user's name never matches one
(`llvm-underscore-dollar` names a type `$anon1`, which until then collided
with the backend's first anonymous record). Modules may have such names too
(`Ss$Def.mod`, `Ss$Def.sym`); on Unix a `$` in a file name needs quoting in
the shell.

## Hexadecimal constants as 64-bit patterns (decided and implemented, Phase 12 step 3, 2026-09-27)

A hexadecimal constant of exactly 16 significant digits (leading zeros do
not count), the first above 7, is above `MAX(HUGEINT)`. poc takes it as the
64-bit two's-complement pattern it spells, a negative value, as voc does
(`OPS.Number`): `0FFFFFFFFD76AA478H` is -680876936, `0FFFFFFFFFFFFFFFFH`
is -1 and `8000000000000000H` is `MIN(HUGEINT)`. The value then takes the
minimal type it fits, like any integer constant: -680876936 is a `LONGINT`
under both size models, so `l + 0FFFFFFFFD76AA478H` stays `LONGINT`
arithmetic. That is how s3's `ethMD5` writes its 32-bit constants. A
constant of fewer digits keeps its value (`0FFFFFFFFH` is 4294967295),
and one of more than 16 is an error, "integer literal too large for
HUGEINT". A decimal constant above `MAX(HUGEINT)` is always an error.
`-strict` rejects the pattern form: "a hexadecimal constant above
MAX(HUGEINT), taken as a 64-bit pattern is not in the Oberon-2 report
(-strict)". Found by the inventory of voc's modules
(`doc/research/voc-module-inventory.md`); decided with the user. Fixtures
`llvm-hex-pattern-literals` and `semantic-strict`.

## Text after the module's end (decided and implemented, Phase 12 step 3, 2026-09-27)

A module ends at the period after `END M`, and poc reads nothing after
it. The report's syntax ends there and says nothing of what follows. A
module kept as an Oberon system text carries its fonts and other data
after the period (s3's `ethUnicode.Mod`), and Oberon compilers, voc
among them, stop at the period. Until then poc lexed on and reported the
first character it could not read. Not an extension, so `-strict` does
not report it. Fixture `llvm-char-string-constants`.


## Record and array literals (decided and implemented, Phase 14, 2026-10-03)

A value of a named record or fixed array type, written in an expression,
and a constant declared by one:

```oberon
TYPE
  Point* = RECORD x*, y*: INTEGER END;
  Line* = RECORD from*, to*: Point; width*: INTEGER := 1 END;
  Vector* = ARRAY 3 OF REAL;
  Matrix* = ARRAY 2, 2 OF REAL;
CONST
  origin* = Point{x := 0, y := 0};
  identity* = Matrix{{1, 0}, {0, 1}};
VAR p: Point; l: Line; v: Vector;
...
  p := Point{x := 3, y := 4};
  l := Line{from := origin, to := p};     (* width gets its default, 1 *)
  v := Vector{1.5, 2.5};                  (* v[2] is 0 *)
  Draw(Line{from := p, to := Point{x := p.x, y := 0}})
```

`Oberon2.pdf` has no structured value: its `Factor` has only the set
constructor. The design, the decisions taken with the user (2026-10-02)
and the survey of other dialects (Modula-3, ISO Modula-2, Micron, Active
Oberon, Oberon+, Ada) are in `doc/developer/record-and-array-literals.md`. Settled
here (2026-10-03), with the user's answers on defaults, on the `.sym`
file and on indexed array elements, and with repeated elements, open
array literals and a bare `{...}` outside a literal left out (each could
come later without changing what is written now). The rules:

- **The syntax**: `Literal = Qualident "{" [Element {"," Element}] "}"`,
  where `Element = [ident ":=" | "[" CaseLabelList "]" ":"] (Expression
  | "{" ... "}")`.
  `Qualident` names a record type or an array type of fixed length:
  never a pointer type, an open array type or an anonymous type (there
  is none to name: types are equivalent by name). A designator is never
  followed by `{` in Oberon-2, so the form is new and unambiguous. A
  literal is a factor, not a designator: no selector follows it.
- **Record elements are named**, `field := expression`, each a field of
  the type or of one of its base types, each at most once, in any
  order; never positional ("a record literal names its fields: field :=
  value"). **Array elements are positional**, from index 0, at most the
  array's length, **or indexed**, `[labels]: expression`, the labels
  written as a `CASE`'s, constant integers and ranges within the array's
  bounds: `Class{[ORD("0") .. ORD("9")]: digit, [ORD("_"), 0]: other}`
  (user, 2026-10-03). The two mix: a positional element takes the index
  after the one before it, after an indexed element the index after the
  highest it gives (`Vec{1, 2, [5]: 50, 60}` sets 0, 1, 5 and 6). No
  index may be given twice ("this index is given twice in the literal");
  an index is not allowed in a record literal or a set. A
  multi-dimensional array is an array of arrays: `Matrix{{1, 0}, {0,
  1}}`.
- **Each element is assignment compatible** with its field or element
  type, as `Oberon2.pdf` Appendix A defines it and poc extends it: a
  string for an `ARRAY n OF CHAR`, an extension's record (projected) for
  a record field, `NIL` for a pointer or procedure, an integer constant
  that fits a smaller integer type.
- **A nested literal may leave out its type's name**: where an element's
  type is a record or array type, `{...}` is a literal of that type
  (which is how a field or element of an anonymous type gets one at
  all); where it is a set type, `{...}` is a set constructor, ranges
  included; anywhere else it is an error. Outside a literal `{...}` is
  always a set, as in the report.
- **Omitted elements take their defaults.** A literal's value is made
  exactly as a variable of its type is: zeroed, then every field
  initializer applied (Phase 11 D17: the base type's first, through the
  type's initialization procedure, in every record inside it and in
  every element of an array of records), and then the elements written
  are evaluated and assigned in the order written, each once - an
  indexed element once for each index it gives, in increasing order
  within a range, so `[0..9]: NewNode()` makes ten nodes. So a field
  that is written also has its default evaluated first, as for `VAR r:
  T; ... r.x := e` (user, 2026-10-03: an imported type's defaults exist
  only as its declaring module's procedure, which applies all of them),
  and a nested literal makes its own value the same way before it is
  assigned to its element. The value is complete before it is used, so
  `r := R{x := r.y, y := r.x}` swaps.
- **No literal of a record type with a field hidden or read-only where
  the literal is written**: a field not exported, or exported with `-`,
  by another module (base types' fields included) means that module's
  literals cannot name the type ("no literal of this type can be written
  here; this field is not exported by its module: f", or "is read-only
  outside its module"). The declaring module, which
  sees every field, can. A record of such a type can still be an element
  given by a variable, or an omitted one.
- **Where a literal may stand**: wherever an expression of its type may
  - the source of an assignment (to a variable, a field, an element,
  `p^`), a value parameter, an open array value parameter (an array
  literal), an element of another literal, a variable or field
  initializer. Not where a variable is needed: a `VAR` parameter,
  `SYSTEM.ADR`, a type guard, `IS`. `=` and `#` stay undefined on records
  and arrays.
- `-strict` rejects a literal ("a record or array literal is not in the
  Oberon-2 report (-strict)"), and voc cannot compile one.

**Structured constants.** A literal is a constant expression when every
element written is a constant, structured constants included, and every
omitted element's default is constant: zero, or a field initializer
whose value is constant. A pointer or procedure element of one can only
be `NIL`. Then `CONST c = T{...}` declares a constant of type `T`, which
as every Oberon constant states no type of its own. The rules:

- A field initializer that is not constant makes a constant literal give
  that field ("the default of this field is not constant, so a constant
  literal must give it: f"); a literal that is not in a `CONST` may leave it out.
- **Read-only**: a structured constant is used as a read-only variable of
  its type is: read, assigned from, passed as a value or open array value
  parameter, an element of another literal. Never assigned to, passed as
  a `VAR` parameter or to `SYSTEM.ADR`.
- **Selecting from one**: `origin.x`, and `identity[1, 1]` with constant
  indexes, are constant expressions, folded like any other, so a
  constant table can give a `CASE` label or an array length. A constant
  index out of range is a compile-time error. An index that is not
  constant reads the constant's copy in memory, index-checked as usual.
  `LEN` of one is a constant, as of any fixed array.
- **In memory**: each module that needs one in memory (to pass it, to
  assign it, to index it with a variable) has its own private, read-only
  copy, made from the value, as a scalar constant is folded into each
  module that uses it rather than linked from its exporter.
- **Exported**: the `.sym` file writes the constant as its literal,
  `origin* = Point{x := 0, y := 0};`, every field of a record given,
  defaults and hidden fields included, and an array's elements by
  position as far as its literal gives them (indexed elements written
  out, the gaps with their defaults; the rest are its element type's
  default, which the reader computes the same way); in a `CONST` section after the `TYPE` section (a literal
  names its type, and the reader declares before use; `DeclSeq` allows
  the sections in any order). The importer folds `M.origin.x` from it and
  makes its own copy from it; it cannot select a hidden field, and the
  `.sym` reader is exempt from the visibility rule above. The constant's
  type must have a name the `.sym` file can use: a `TYPE` of the module,
  exported or not (an unexported one is declared in the `.sym` file, as
  for a variable of that type), or an exported one of an import ("an
  exported record or array constant's type must have a name"), so
  `row* = m[1]` of an `ARRAY 2, 2` cannot be exported.
- **Field initializers in the `.sym` file**: a field initializer whose
  value is constant is written as that value, `f: INTEGER := 3`, hidden
  fields' included, so an importer can fold a constant literal that
  leaves the field out (user, 2026-10-03); one that is not constant is
  written `:= ..`, as before (Phase 11 D17).

Implemented in Phase 14 steps 2-4. The LLVM backend makes each literal in a
stack slot of its own, allocated in the entry block of the function that
evaluates it (so a literal in a loop does not grow the stack), and loads it
from there or passes its address; a structured constant that is needed in
memory is a private constant global of the module.

## QUOT and REM (decided 2026-10-05, not yet implemented; Phase 19, candidate 4)

**Adopted by the user 2026-10-05, to be implemented later** (the decision is
at the end of this section). `DIV` and `MOD` floor ("Overflow, division and
reals" above): `-7 DIV 2` is -4 and `-7 MOD 2` is 1. Ada and C divide the
other way: their integer `/` truncates toward zero, and the remainder that
goes with it (Ada's `rem`, C's `%`) has the dividend's sign, so `-7 / 2` is
-3 and `-7 rem 2` is -1. Ada's `mod` is Oberon's `MOD`, but Ada has no floor
quotient and Oberon no truncated one. A program ported from Ada or C to poc
(the user's Ropes came from Ada) has only expressions built from `DIV`,
`MOD` and the operands' signs for the truncated pair, which are easy to get
wrong.

**The extension**: two predeclared function procedures.

- `QUOT(x, y)`: the quotient of the integers `x` and `y`, truncated toward
  zero - Ada's integer `/`, C's `/`, LLVM's `sdiv`.
- `REM(x, y)`: the remainder that goes with it, with the dividend's sign
  and an absolute value less than `y`'s, so that `x = QUOT(x, y) * y +
  REM(x, y)` - Ada's `rem`, C's `%`, LLVM's `srem`.

**Why a pair**: `REM` alone would leave a program writing its truncated
quotient by hand, and the two are useful only together, as `DIV` and `MOD`
are; Ada's identity `A = (A/B)*B + (A rem B)` needs both.

**Why predeclared functions, not operators**: an operator needs a reserved
word, and a new reserved word breaks every existing program that has a
`REM` of its own. A predeclared name breaks none: a module may declare its
own `REM`, as it may its own `ASSERT` ("ASSERT" above). ISO Modula-2 has
the truncated pair as operators, but it was a new language; and its
quotient is `/`, which Oberon keeps for reals - making `i / j` of two
integers an integer would change the meaning of every such expression in
an existing program.

**The rest, as for `DIV` and `MOD`** (to be confirmed when it is built):

- The operands are integers, of any integer type, and the result has the
  type that includes both, as `DIV`'s does.
- Constant operands fold to a constant.
- A zero divisor, and `QUOT(MIN(T), -1)`, are not checked: `SIGFPE` on
  x86, a value on aarch64, as for `DIV` ("What traps, and what does not").
- `-strict` rejects both: "QUOT is not in the Oberon-2 report (-strict)".
- The Reference Guide gets a section among the extensions, and the User's
  Guide a line where it shows `DIV` and `MOD`.

**The survey** (2026-10-05, `doc/research/truncating-division-survey.md`):

- **No Oberon has it**, in the language or a standard library: not the
  reports (Oberon, Oberon-2, Oberon-07, the revised Oberon-2, Component
  Pascal, Active Oberon, Oberon+, the Oakwood Guidelines), nor voc, Ofront,
  OfrontPlus, oo2c, obc, OBNC, A2, BlackBox, Linz Oberon V4 or Native
  Oberon. Component Pascal and Modula-3 floor for either sign, as poc does.
- **ISO Modula-2 is the one precedent**: `/` on integers truncates and
  `REM` is its remainder, beside a floor `DIV` and `MOD` defined for a
  positive divisor only. Wirth's PIM2 and PIM3 had the truncated pair
  under the names `DIV` and `MOD`, and PIM4 changed `MOD` to be never
  negative; Oberon kept the names with floor meanings.
- **Modula-3** has only the floor pair; its `Word.Divide` and `Word.Mod`
  are for unsigned words.

**Decided with the user, 2026-10-05**: adopted, as `QUOT(x, y)` and
`REM(x, y)`, predeclared function procedures, and the two together - `REM`
is no use without `QUOT` (the user). Not built yet: Phase 19 does it, with
fixtures for each sign of each operand, constants and variables, every
integer type, and `-strict`.

## Unsigned integer types (decided 2026-10-08, not yet implemented; Phase 19, candidate 5)

**Adopted by the user 2026-10-08, to be implemented later.** The FLTK binding (`~/Repos/Oberon/pofltk`)
declares C's unsigned types as the signed `SYSTEM.INTn` of the same width,
which pass the bits but compare, divide and widen as signed: `Fl.RGB`
builds an `Fl_Color`, a C `unsigned int`, with `SYSTEM.VAL`, and a color
whose red is 128 or more is a negative `INTEGER` under `-OC`.

**The extension**: four types in SYSTEM, `SYSTEM.CARD8`, `CARD16`,
`CARD32` and `CARD64`, the integers 0 to 2^n - 1 in exactly n bits under
both size models (XDS's names, `SYSTEM.CARD8` to `CARD32`, with a 64-bit
one added).

- **`SYSTEM.CARD`** (decided with the user, 2026-10-08): unsigned and as
  wide as `SYSTEM.ADDRESS`, 32 or 64 bits by the target, for C's `size_t`
  and `uintptr_t` and for comparing addresses unsigned (on the VAX, system
  space starts at 80000000H). Like `ADDRESS`, a type of its own rather than
  an alias of `CARD32` or `CARD64`, so that code passing it as a `VAR`
  parameter compiles at either width; it and the `CARDn` of its width
  include each other, and in every other way it is a CARD type
  (`SYSTEM.VAL(SYSTEM.CARD, a)` of an `ADDRESS` is its bits). There is no
  signed counterpart: `ADDRESS` is the signed word-sized type.
- **A family of their own**: `CARD8 ⊆ CARD16 ⊆ CARD32 ⊆ CARD64`, apart from
  the signed integers, as the Oakwood Guidelines recommend and XDS does.
  No CARD type is included in a signed one, nor a signed one in a CARD
  type, so an expression, comparison or assignment that mixes the families
  is an error. Both families are included in `REAL ⊆ LONGREAL` (decided
  with the user), so `c * 1.5` is a real expression, as in XDS.
- **Constants**: a non-negative integer constant whose value fits is
  usable with a CARD type, as with `SYSTEM.INTn` (`c + 1`, `c := 255`,
  `IF c = 0`). A negative constant is an error. `MIN(SYSTEM.CARDn)` is 0
  and `MAX(SYSTEM.CARDn)` is 2^n - 1.
- **`CARD64` values above `MAX(HUGEINT)`** are written as hexadecimal
  patterns ("Hexadecimal constants as 64-bit patterns"): with a `CARD64`,
  `0FFFFFFFFFFFFFFFFH` is 2^64 - 1 (as a signed integer it stays -1), and
  `08000000000000000H` is 2^63; or as `MAX(SYSTEM.CARD64)`. A decimal
  literal above `MAX(HUGEINT)` is still an error (decided with the user).
- **`FOR` with a CARD control variable** may count down: a negative `BY`
  steps by subtraction, `v := v - |inc|`, modulo 2^n (decided with the
  user). Under the report's rule, `WHILE v >= temp DO S; v := v + step
  END`, `FOR c := 10 TO 0 BY -1` would wrap `c` from 0 to `MAX`, still
  `>= 0`, and never end. Every `FOR` therefore ends before a step that
  would pass `temp` (decided with the user; "FOR final value" above), so
  it runs for 10 down to 0 and stops, and so does a loop up to
  `MAX(SYSTEM.CARDn)`.
- **Between the families, `SYSTEM.VAL` only** (decided with the user): no
  checked conversion and no new procedure, so every crossing is marked as
  a reinterpretation. `SYSTEM.VAL(SYSTEM.CARD32, -1)` is
  `MAX(SYSTEM.CARD32)`. Between sizes, poc's `SYSTEM.VAL` extends or
  truncates, and the extension follows the source's family: a CARD is
  zero-extended, a signed value sign-extended. So `SYSTEM.VAL(LONGINT, c)`
  of a `CARD16` is its value, and `SYSTEM.VAL(SYSTEM.CARD32, i)` of a
  negative `INTEGER` under `-O2` is its sign-extended bits.
  `SYSTEM.VAL` also converts between a CARD and `SET` or `SYSTEM.SET64` of
  its width.
- **Within the family, `SHORT` and `LONG`** (decided with the user): `LONG`
  zero-extends to the next CARD size, `SHORT` keeps the low bits of the
  next smaller one and, with `-range-checks`, traps on a value that does
  not fit (status 14), as it does for signed integers.
- **Arithmetic wraps on overflow and underflow** (the user): `+`, `-`,
  `*`, `INC` and `DEC` are modulo 2^n, so `MAX + 1` is 0 and `0 - 1` is
  `MAX`. **Unary minus is allowed** (decided with the user) and is `0 - x`,
  modulo 2^n. `ABS` is the identity.
- **Comparison, `DIV` and `MOD` are unsigned** (LLVM's `icmp ult`, `udiv`,
  `urem`). Floor and truncation agree for these values. A zero divisor is
  not checked, as for the signed types ("What traps, and what does not").
- **Shifts**: `ASH` and `SYSTEM.LSH` of a CARD shift right with zeros.
  `SYSTEM.ROT` rotates within its width.
- **Other predeclared procedures**: `ODD` as for any integer; `CHR` of a
  CARD as of any integer. `ORD`, `LEN` and `SIZE` keep their signed result
  types, so `c < LEN(a)` of an open array needs `SYSTEM.VAL`.
- **`SYSTEM.BYTE`** takes a `CARD8`, as it takes a `CHAR` or a one-byte
  `SHORTINT`.
- **`-strict`** rejects them: "SYSTEM.CARD32 is not in the Oberon-2 report
  (-strict)". voc has no such types, so a program that uses them builds
  with poc only, and poc's own source cannot use them.

**What it touches**: Appendix A's type predicates; the constant evaluator,
which must fold up to 2^64 - 1, unsigned (with `HUGEINT` patterns, since
poc's source is strict Oberon-2), and the `.sym` format, which must write a
`CARD64` constant above `MAX(HUGEINT)`; the LLVM backend's operators
(`udiv`, `urem`, `icmp ult`, `zext`, `lshr`, `uitofp`, `fptoui`, unsigned
index checks) and debug information (`DW_ATE_unsigned`); the VAX backend
(its unsigned branches, `MOVZ`, and runtime routines for `DIV` and `MOD`,
since `EDIV` is signed); and the runtime's text modules, since `Out.Int`
takes a `HUGEINT` and no CARD converts to one implicitly: `Out`, `Err`,
`OutStr` and `FormattedText` need procedures that write a CARD in decimal
and hexadecimal, and `In` and `InStr` ones that read one ("Ongoing library
enhancements").

**The survey** (2026-10-08, `doc/research/unsigned-survey.md`): the
Oberon-2, Oberon and Component Pascal reports have no unsigned types;
Oberon-07 and Oberon+ only an unsigned `BYTE`. The Oakwood Guidelines
(1995) record ETH's rejection of unsigned types and recommend, for any
added family, a separate inclusion hierarchy, explicit conversion between
hierarchies, and `LONG` and `SHORT` within each. XDS has
`SYSTEM.CARD8` to `CARD32` that way, for interfaces to foreign libraries.
Active Oberon has `UNSIGNED8` to `UNSIGNED64` in one chain with the signed
types, a signed value going into an unsigned type of its size without a
conversion. GNU Modula-2 has `SYSTEM.CARDINAL8` to `CARDINAL64`, never
mixed with the signed types in an expression. Modula-3, and Oberon System
3's `BIT` module, give unsigned operations on signed types as procedures.

**Decided with the user, 2026-10-08**: option 2 of the survey, a separate
family, with a 64-bit type; named `SYSTEM.CARD8`, `CARD16`, `CARD32` and
`CARD64`, and `SYSTEM.CARD` of address width with no signed counterpart;
`SYSTEM.VAL` the only conversion between the families; `SHORT`
and `LONG` within it; included in `REAL` and `LONGREAL`; unary minus
allowed; wrapping on overflow and underflow; no decimal literals above
`MAX(HUGEINT)`, hexadecimal patterns instead; `FOR` counting down by
subtraction, and every `FOR` ending before a step past its final value. Not built yet: Phase 19 does
it, with fixtures for each operation at each width, constants, `SHORT`
and `LONG`, `SYSTEM.VAL` both ways, mixing errors, `-strict`, and the
text modules.
