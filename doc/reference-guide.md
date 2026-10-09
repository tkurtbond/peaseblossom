# The Peaseblossom Reference Guide

What `poc`, the Peaseblossom Oberon-2 compiler, accepts and does, exactly.
It is a companion to the language report, `Oberon2.pdf` (H. Mössenböck and
N. Wirth, *The Programming Language Oberon-2*, in its later revision, not
the ETH technical report of October 1993), which it refers to by section
and does not reproduce: where this guide says nothing, the report's rule
holds as written.

The User's Guide (`users-guide.md`) shows how to use poc; this guide is
where to look up a rule. `doc/developer/language-extensions.md` in poc's source is
the design document for each extension below: why it was adopted, what was
considered, and how poc builds it. This guide documents each one as it is
implemented, what a program can write and what it gets. `poc(1)` is the
manual page for the command line.

This guide describes poc 0.4 with its LLVM backend, on Linux, NetBSD,
OpenBSD and FreeBSD.

## Contents

1. [Targets and the basic types](#1-targets-and-the-basic-types)
2. [Choices the report leaves to the implementation](#2-choices-the-report-leaves-to-the-implementation)
3. [Extensions](#3-extensions)
4. [The module SYSTEM](#4-the-module-system)
5. [Exact rules for constants and arithmetic](#5-exact-rules-for-constants-and-arithmetic)
6. [Traps and exit statuses](#6-traps-and-exit-statuses)
7. [The command line](#7-the-command-line)
8. [Files and formats](#8-files-and-formats)
9. [The runtime modules](#9-the-runtime-modules)

## 1. Targets and the basic types

A target is an LLVM target triple: by default clang's own for the host,
otherwise the one `-target` names. poc has been run on x86_64 Linux,
NetBSD and FreeBSD, i386 OpenBSD, and aarch64 FreeBSD. The target fixes
the *word size*, 4 or 8 bytes: the size of a pointer, a procedure value and
`SYSTEM.ADDRESS`.

The *size model* fixes the integer types' sizes, as voc's do: `-O2`, the
default, has the classic Oberon-2 sizes; `-OC` has Component Pascal's. A
program and every module it imports are compiled under one model; a module
compiled under one does not link with a program compiled under the other.

| Type | `-O2` | `-OC` | Values |
|---|---|---|---|
| `BOOLEAN` | 1 | 1 | `FALSE`, `TRUE` |
| `CHAR` | 1 | 1 | `0X`..`0FFX`; no character set is implied |
| `SHORTINT` | 1 | 2 | -2^7..2^7-1, or -2^15..2^15-1 |
| `INTEGER` | 2 | 4 | -2^15..2^15-1, or -2^31..2^31-1 |
| `LONGINT` | 4 | 8 | -2^31..2^31-1, or -2^63..2^63-1 |
| `HUGEINT` | 8 | 8 | -2^63..2^63-1 |
| `REAL` | 4 | 4 | IEEE 754 single precision |
| `LONGREAL` | 8 | 8 | IEEE 754 double precision |
| `SET` | 4 | 4 | subsets of 0..31 |
| `SYSTEM.SET64` | 8 | 8 | subsets of 0..63 |
| `SYSTEM.BYTE` | 1 | 1 | a byte |
| `SYSTEM.INT8`, `INT16`, `INT32`, `INT64` | 1, 2, 4, 8 | 1, 2, 4, 8 | two's complement of that width |
| `SYSTEM.ADDRESS` | word | word | an integer as wide as a pointer |
| pointers, procedure values, `SYSTEM.PTR` | word | word | `NIL` or an address |

Sizes are in bytes. Integers are two's complement. `MAX(REAL)` is
3.4028234663852886E38 and `MAX(LONGREAL)` 1.7976931348623157D308, IEEE
754's largest finite values; `MIN` of each is its negation.

**Layout.** A type is aligned to its own size, at most the word size: on a
32-bit target an 8-byte `LONGREAL`, `HUGEINT` or record is aligned to 4. A
record's fields follow its base type's, each at its alignment, and the
record is padded to its own alignment, the largest of its fields' and its
base type's. A fixed array is its elements, one after the other. `SIZE(T)`
gives this size.

**Open arrays.** An open array parameter is passed as the address of its
first element and one word-sized length per open dimension, outermost
first. A pointer to an open array points at a block that starts with the
lengths, one word each, followed by the elements (voc's layout).

## 2. Choices the report leaves to the implementation

- **Integer sizes**: section 1.
- **Initial values**: every variable starts at zero - global, local (on
  every entry to its procedure), and in a heap block - so a number is 0, a
  `BOOLEAN` `FALSE`, a `CHAR` `0X`, a set `{}`, and a pointer or procedure
  value `NIL`, in records and arrays too. `Oberon2.pdf` §6.4 asks this of
  pointers only.
- **`&` and `OR`** evaluate their right operand only when it decides the
  result (Appendix A).
- **Identifiers** may be up to 255 characters long; a longer one is an
  error. Case is significant, as in the report. **Strings** have no length
  limit.
- **`HALT(n)`**: `n` must be a constant in 0..255 (a compile-time error
  otherwise); the program ends with exit status `n`, writing nothing.
- **`CASE`**: a label must lie in the range of the selector's type (a
  compile-time error otherwise); a value no label matches, with no `ELSE`,
  is a trap (section 6).
- **`COPY(x, v)`** copies up to `x`'s `0X`, at most `LEN(v) - 1`
  characters, and always ends `v` with a `0X`; a source with no `0X` is
  read to its end.
- **Comparing character arrays**: the end of an array with no `0X` counts
  as one.
- **`LEN`** is a `LONGINT`. `LEN("abc")` is 4: a string passed to an open
  array counts its `0X`.
- **Integer overflow, `DIV` and `MOD`, reals, `ENTIER`**: section 5.
- **Text after the module's end**: nothing after the period of `END M.` is
  read, as in Oberon compilers generally (an Oberon system text keeps its
  fonts there).
- **The order of module initialization**: a module's body runs once, after
  the bodies of the modules it imports, in the order of its `IMPORT` list.

## 3. Extensions

Each extension below is an error under `poc -strict`, and each section ends
with the error's message. Only the module named on the command line is
checked; the modules it imports are not, so a strict module may import one
that uses extensions. poc's own source is checked with `-strict`. The
heading of each item is that of its section in
`doc/developer/language-extensions.md`.

### HUGEINT

An 8-byte signed integer, predeclared, under both size models. In the
inclusion hierarchy of Appendix A it lies between `LONGINT` and `REAL`:
`LONGREAL` ⊇ `REAL` ⊇ `HUGEINT` ⊇ `LONGINT` ⊇ `INTEGER` ⊇ `SHORTINT`, so
every rule that goes by that order applies to it. Under `-OC`, `LONGINT`
and `HUGEINT` have the same size and are still different types. An integer
constant whose value needs more than `LONGINT` is a `HUGEINT`.

Under `-strict`, naming `HUGEINT` is an error, `HUGEINT is not in the
Oberon-2 report (-strict)`, and so is a constant too large for `LONGINT`:
`an integer constant too large for LONGINT is not in the Oberon-2 report
(-strict)`.

### Variable initializers

```oberon
VAR
  count: INTEGER := 0;
  a, b: INTEGER := Next();
  name: ARRAY 16 OF CHAR := "none";
```

The initializer is an assignment of its expression to each variable of the
list, with every rule of an assignment, evaluated once for each variable,
in the order of the names. A module's variables are assigned before its
body runs, a procedure's on every entry to it before its body, all in
declaration order. Any expression is allowed; it can use only the names
declared before its `:=`. Parameters have none.

Under `-strict` an initializer is an error: `a variable initializer is not
in the Oberon-2 report (-strict)`.

### Record field initializers

```oberon
TYPE
  Point* = RECORD x*, y*: INTEGER := 1; tag: CHAR := "p" END;
```

The defaults of a record's fields, assigned whenever a record of the type is
made: a variable, `NEW` (of a record, or of an array of records: every
element), and a record inside one of those, at any depth. Not when a record
is copied, and not in a `SYSTEM.NEW` block. The base type's defaults come
first, then the record's own fields in order; each field of a list gets its
own evaluation. The expression can use the names declared before its `:=`,
except, for a record declared in a procedure, that procedure's variables,
parameters and procedures. A module that imports the type gets its
defaults, hidden fields' included.

Under `-strict` a field's initializer is an error: `a record field
initializer is not in the Oberon-2 report (-strict)`.

### Record and array literals

```oberon
TYPE
  Point* = RECORD x*, y*: INTEGER END;
  Line* = RECORD from*, to*: Point; width*: INTEGER := 1 END;
  Matrix* = ARRAY 2, 2 OF REAL;
CONST
  origin* = Point{x := 0, y := 0};
  identity* = Matrix{{1, 0}, {0, 1}};
...
  line := Line{from := origin, to := {x := 3, y := 4}};
```

`T{...}` is a value of `T`, a named record type or array type of fixed
length. A record's elements are named, `field := e`, each a field of the
type or of a base type, at most once, in any order; an array's are
positional from index 0, at most its length, or indexed, `[labels]: e`,
the labels constant integers and ranges written as a `CASE`'s. A
positional element after an indexed one takes the index after the highest
it gives, so `Vec{1, [5]: 50, 60}` sets 0, 5 and 6; no index may be given
twice. An indexed element is evaluated once for each index it gives, in
increasing order within a range. Each element is assignment
compatible with its field or element, an array element may also be a
shorter array ("Array assignment" below). Inside a literal, `{...}` is a
literal of the element's type when that is a record or array type, and a
set when it is a set type; elsewhere `{...}` is a set, as in the report. A
literal is made as a variable of its type is - zeroed, then every field
initializer - and then its elements are evaluated and assigned in the
order written, so `p := Point{x := p.y, y := p.x}` swaps. A literal is a
factor: no selector follows it, and it is not a variable (not a `VAR`
parameter). A literal of another module's record type with a field hidden
or read-only there cannot be written ("no literal of this type can be
written here; this field is not exported by its module").

Under `-strict` a literal is an error: `a record or array literal is not in
the Oberon-2 report (-strict)`.

A literal is a constant expression when every element written is constant
and every omitted field's default is constant, and then `CONST c = T{...}`
declares a structured constant. It is used as a read-only variable is: never
assigned to or passed as a `VAR` parameter. `origin.x` and `identity[1, 1]`
are constants; an index that is not constant reads a copy of the constant in
memory, checked as usual. A pointer or procedure element of one is `NIL`. An
exported one's type must have a name the `.sym` file can use: a type of the
module, or an exported one of an import.

### Declarations after procedures

`CONST`, `TYPE` and `VAR` sections may follow procedures, in a module and in
a procedure, not only precede them. Declare-before-use is unchanged: a
procedure's body sees only what is declared above it. A section after a
procedure may not declare a name visible from an enclosing scope, and the
base type of a `POINTER TO` must be declared before the next procedure.

Under `-strict` such a section is an error: `a CONST, TYPE or VAR section
after a procedure is not in the Oberon-2 report (-strict)`.

### ASSERT

`ASSERT(x)` and `ASSERT(x, n)`: `x` a `BOOLEAN` expression, `n` an integer
constant in 0..255. When `x` is `FALSE` the program stops with "assertion
failed" or "assertion failed (*n*)" and exit status 10. `x` is always
evaluated; nothing turns assertions off. A condition that is a constant
`FALSE` is a compile-time error, so `ASSERT(SIZE(T) = 8)` is checked by the
compiler. A module may declare its own `ASSERT`.

Under `-strict` calling the predeclared `ASSERT` is an error: `ASSERT is not
in the Oberon-2 report (-strict)`.

### External procedures

```oberon
PROCEDURE ["C"] getpid*(): SYSTEM.INT32;
PROCEDURE ["C", "malloc"] AllocateBytes*(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
```

A procedure declared with a calling convention and no body is defined
elsewhere. `"C"` is the C calling convention; the second string, if there
is one, is the name to link with, used as it is; without it, the
procedure's own name. A `VAR` parameter is passed as the variable's
address, an open array as its first element's address alone (no lengths),
and a `VAR` record without its type. An external procedure is not a
procedure value. `"VMS"` is the VMS calling standard, for the VAX/VMS
target (`-emit-macro32`): a value parameter of a longword or less is
passed by value, a `VAR` one by reference. The User's
Guide, "Calling C", shows the C types' equivalents.

Under `-strict` the declaration is an error: `an external procedure is not
in the Oberon-2 report (-strict)`.

### Underscores and dollar signs in identifiers

`_` and `$` may appear in an identifier anywhere a letter may, first
included: `SS$_NORMAL`, `DSC$W_LENGTH`.

Under `-strict` each is an error: `"_" in an identifier is not in the
Oberon-2 report (-strict)`, and `"$" in an identifier is not in the Oberon-2
report (-strict)`.

### Hexadecimal constants as 64-bit patterns

A hexadecimal constant of exactly 16 significant digits, the first above 7,
is the negative number its bits spell in 64-bit two's complement:
`0FFFFFFFFFFFFFFFFH` is -1, `0FFFFFFFFD76AA478H` is -680876936 (a
`LONGINT`). Fewer digits keep their value; more is an error.

Under `-strict` such a constant is an error: `a hexadecimal constant above
MAX(HUGEINT), taken as a 64-bit pattern is not in the Oberon-2 report
(-strict)`.

### Array assignment

`v := e`, where `v` is a fixed array and `e` an array with the same element
type that is a fixed array no longer than `v` or an open array. All of `e`
is copied, whatever it holds, and the rest of `v` is left as it was. An
open `e` longer than `v` is a trap (status 9). An open array is never the
target.

Under `-strict` such an assignment is an error: `assigning an array of
another type (voc's array rule) is not in the Oberon-2 report (-strict)`.

### SYSTEM.SET32 and SYSTEM.SET64

`SYSTEM.SET64` is a set of 0..63, 8 bytes; `SYSTEM.SET32` is `SET`. A `SET`
is included in a `SET64`, not the reverse. A constant set has the narrowest
set type its value fits: `{0, 31}` is a `SET`, `{0, 32}` a `SET64`. A
constructor with a variable element is a `SET`, or a `SET64` if it has a
constant element above 31.

Under `-strict`, naming either type is an error, as `SYSTEM.SET32 is not in
the Oberon-2 report (-strict)` and `SYSTEM.SET64 is not in the Oberon-2
report (-strict)`; so is a set constant with an element above 31, `a set
constant with an element above MAX(SET) is not in the Oberon-2 report
(-strict)`, and a constructor's element above 31, `a set element above
MAX(SET) is not in the Oberon-2 report (-strict)`.

### Read-only parameters

A formal parameter written `x-`, as in voc: `PROCEDURE Length(s-: ARRAY OF
CHAR): INTEGER`. Inside the procedure, assigning to `x` or any part of it is
an error, and so is passing it, or any part of it, as a `VAR` argument or as
the `VAR` receiver of a type-bound procedure; it may be passed on as a value
or read-only argument. `VAR x-` is an error. The argument may be any
expression of a type a value parameter would take: a variable, a constant (a
string included), or any other expression - where voc's takes only a
variable. A record or fixed array of more than 16 bytes is passed by
reference, and an open array by reference without being copied; a constant
is passed as a reference to its own storage. Any other type is passed by
value, as a value parameter is. The size is `SIZE`'s, which depends on the
size model and the target, so the same type may be passed one way under
`-O2` and the other under `-OC`, or on 32-bit x86 and on x86_64. A program
may not rely on which: if the argument is a variable that the procedure
changes by another name (a global, a `VAR` parameter), it may see the old
value or the new one. Procedure types and redefined type-bound procedures
must match mark for mark. A `.sym` file keeps the mark.

Under `-strict` declaring one is an error, `a read-only parameter is not in
the Oberon-2 report (-strict)`; calling an imported procedure that has one
is allowed.

### Other extensions

- **`ORD` of a set** is its bits as an integer: an `INTEGER` for a `SET`, a
  `HUGEINT` for a `SET64`. Under `-strict` it is an error: `ORD of a SET is
  not in the Oberon-2 report (-strict)`.
- **`SYSTEM.PTR`** compares with a pointer of any type. Under `-strict` it
  is an error: `comparing SYSTEM.PTR with another pointer type is not in the
  Oberon-2 report (-strict)`.
- **`SYSTEM`'s names beyond Appendix C** (section 4): `ADDRESS`, `INT8`,
  `INT16`, `INT32`, `INT64`, `SET32`, `SET64`. Under `-strict` naming one is
  an error, such as `SYSTEM.INT32 is not in the Oberon-2 report (-strict)`.

### Not extensions, though the report differs

- **The final value of `FOR`**: in `FOR v := low TO high`, `high` must be
  assignment compatible with `v`, as `low` is, where §9.8 asks only that it
  be comparable: a wider or real `high` is a compile-time error. `low` is
  assigned to `v` before `high` is evaluated, once.
- **A guard, `IS` or `WITH` on a pointer names a pointer type**, never a
  record type; `=` and `#` compare pointers of related types only, and
  procedure values of one type only.
- **An export mark on a formal parameter**, `x*`, is a syntax error; `x-`
  is a read-only parameter (section 3).

## 4. The module SYSTEM

`IMPORT SYSTEM` gives Appendix C's low-level facilities, as follows. An
address is a `SYSTEM.ADDRESS`. Using them makes a module unsafe in the
report's sense: nothing checks what they do.

| Name | What it is |
|---|---|
| `ADDRESS` | An integer type as wide as a pointer. Among the integers by size: it and every integer type of its width include each other; a wider one includes a narrower and not the reverse. So under `-OC` an `ADDRESS` is assignable to a `LONGINT` on every target, and a `LONGINT` to an `ADDRESS` only on a 64-bit one. |
| `ADR(v)` | The address of the variable `v`: an `ADDRESS`. |
| `BIT(a, n)` | Bit `n MOD 8` of the byte at `a + n DIV 8` (floored), bit 0 the lowest: a bit string starting at `a`, for any `n`. One byte is read. |
| `GET(a, v)`, `PUT(a, x)` | Read `v`, or write `x`, at address `a`, at the type of `v` or `x` (a bare numeral at its minimal type), with no alignment assumed. |
| `MOVE(a0, a1, n)` | Copies `n` bytes from `a0` to `a1`; nothing when `n <= 0`. |
| `VAL(T, x)` | `x`'s bits as a `T`; between scalars of different sizes, sign-extended or truncated. |
| `LSH(x, n)`, `ROT(x, n)` | `x` shifted or rotated left by `n`, right for a negative `n`, at `x`'s own width; the result has `x`'s type. `LSH` by the width or more gives 0; `ROT` counts modulo the width. |
| `NEW(v, n)` | `n` zeroed bytes for the pointer `v`, which the collector keeps while something points at them but never looks inside: they must not hold the only reference to anything. `n <= 0`, or too large, is a trap (status 7). |
| `BYTE` | One byte. A `CHAR` or `SHORTINT` is assignable to it, not back. A parameter of type `BYTE` takes a `CHAR`, a one-byte `SHORTINT` or a `BYTE`, a `VAR` one a `BOOLEAN` too; a `VAR x: ARRAY OF BYTE` takes a variable of any type, its length the variable's size. |
| `PTR` | A pointer to anything: any pointer is assignable to it. It cannot be dereferenced, `NEW`ed, guarded, tested with `IS` or used in `WITH`; assign it to a typed pointer first. |
| `INT8`, `INT16`, `INT32`, `INT64` | Integers of exactly 1, 2, 4 and 8 bytes under both size models, placed among the integers by size as `ADDRESS` is. An integer constant whose value fits is assignable to each. |
| `SET32`, `SET64` | Section 3. |

`GET`, `PUT` and `MOVE` happen once each, where the program has them,
whatever the optimization. `CC`, `GETREG` and `PUTREG` are not implemented.

## 5. Exact rules for constants and arithmetic

**Constant expressions.** An integer constant expression has the smallest
integer type its value fits, after folding (`2 * 100 + 2 * 10` is the
`INTEGER` 220; `-128` is a `SHORTINT`, `128` an `INTEGER`), in a `CONST`
declaration and in a statement alike. Folding is done in 64 bits, and only a
result outside `HUGEINT` is an error. `ORD`, `ABS`, `CHR`, `CAP`, `ENTIER`,
`LONG`, `SHORT`, `ODD`, `ASH`, `MAX`, `MIN` and `SIZE` of constants fold. A
constant argument that does not fit (`CHR(300)`, `SHORT` of an integer
constant, `ENTIER(1.0E20)`) is a compile-time error. `CAP` changes a
lower-case letter and leaves any other character alone.

- `LEN` of a dimension of fixed length is a constant of type `LONGINT`,
  assignable wherever its value fits (`s := LEN(a)` for a `SHORTINT` `s` and
  an array of 100); an operation on it folds like any other.
- `NIL` is a constant: `CONST none = NIL`.
- `ASH(x, n)` of constants: the count must lie in -62..62, and the result is
  at least a `LONGINT`.
- A constant division by zero, integer or real, is a compile-time error. So
  are a constant index outside a fixed array, a constant length of
  `NEW(p, n)` or size of `SYSTEM.NEW` that is not positive, `FOR ... BY 0`,
  and `LEN(a, n)` past the array's dimensions.

**Integer overflow wraps.** `+`, `-`, `*`, unary `-`, `ABS`, `INC` and `DEC`
that leave their type's range wrap around at the type's width, two's
complement: `MAX(T) + 1` is `MIN(T)`, and `-MIN(T)` and `ABS(MIN(T))` are
`MIN(T)`. This is a promise, at every optimization level.

**`DIV` and `MOD` floor**, for divisors of either sign: `7 DIV -2` is -4,
`7 MOD -2` is -1, and `x = (x DIV y) * y + x MOD y` always. A zero divisor,
and `MIN(T) DIV -1`, are not checked: on x86 the program dies of `SIGFPE`
(exit status 136 in a shell), on aarch64 it goes on with a value. A program
must not depend on either.

**Reals are IEEE 754 and silent**: overflow and a division by zero give an
infinity, `0.0 / 0.0` a NaN, underflow zero or a denormal; `SHORT` of a
`LONGREAL` too large for a `REAL` is an infinity. On 32-bit x86, reals are
computed on the x87, and only at `-opt 0`, the default there, is every
result rounded to its type.

**`ENTIER`** of a value that does not fit a `LONGINT`, an infinity or a NaN
is a trap (status 8): it is the one arithmetic trap.

**`SHORT` and `CHR`** of a value that does not fit keep its low bits
(`CHR(300)` is `","`); with `-range-checks` they trap (status 14).

**`ASH(x, n)`** shifts left by `n`, or right (flooring) for a negative `n`;
the result has the wider of `LONGINT` and `x`'s type. A count of the
result's width or more gives 0, or the sign for a right shift.

**`LONG` and `SHORT`** of the `SYSTEM.INTn` types and `HUGEINT` go by size:
`LONG(x)` is the narrowest of `SHORTINT`, `INTEGER`, `LONGINT` wider than
`x`, else `HUGEINT`; `SHORT(x)` the widest narrower, else `SYSTEM.INT8`.

**Sets**: `x IN s` with `x` outside the set's range is `FALSE`. `INCL`,
`EXCL` and a constructor with a variable element outside the range are not
checked; a constant one is a compile-time error.

**Record assignment.** `v := e` for records, where `v` is a `VAR` parameter
or `p^` whose dynamic type extends its static type, is a trap (status 13),
as §9.1 requires.

## 6. Traps and exit statuses

A trap writes its message and a newline to the standard error stream, then
ends the program with the status below. With `poc -trap-location` the
message starts with the source's file, line and column and ends with the
procedure it is in:

    list.mod:42:15: index out of range (in List.Insert)

| Status | What | Message |
|---|---|---|
| 2 | An index out of range: a fixed array, an open array, a pointer to an open array | `index out of range` |
| 3 | `CASE` with no matching label and no `ELSE` | `no matching CASE label` |
| 4 | A `NIL` dereference: `p^`, `p.f`, `p[i]`, `NIL IS T`, `NIL(T)`, a `NIL` `WITH` variable, a call of a `NIL` procedure value, a type-bound call on a `NIL` receiver | `NIL pointer dereference` |
| 5 | A type guard that fails | `type guard failed` |
| 6 | `WITH` with no matching branch and no `ELSE` | `no matching WITH guard` |
| 7 | `NEW(p, n, ...)` or `SYSTEM.NEW(v, n)` with a length that is not positive, or a size beyond the address space | `Too many, or negative number of, elements in dynamic array` |
| 8 | `ENTIER` of a value that does not fit a `LONGINT`, an infinity or a NaN | `ENTIER argument out of range for LONGINT` |
| 9 | An open array assigned to a fixed array with fewer elements | `open array assigned to an array too short for it` |
| 10 | `ASSERT` whose condition is `FALSE` | `assertion failed`, or `assertion failed (n)` |
| 11 | Only with `-trap-heap-exhausted`: a `NEW` or `SYSTEM.NEW` the heap cannot satisfy | `heap exhausted: NEW cannot allocate the block` |
| 12 | A function procedure that reaches its `END` | `function procedure reached its END without RETURN` |
| 13 | A record assigned to a `VAR` parameter or `p^` whose dynamic type extends its static type | `record assigned to a variable whose dynamic type extends its static type` |
| 14 | Only with `-range-checks`: `SHORT` of an integer, or `CHR`, of a value that does not fit | `SHORT argument out of range`, `CHR argument out of range` |

Every trap ends the program after its finalizers have run
(`GarbageCollectedHeap.RegisterFinalizer`).

Without `-trap-heap-exhausted`, a `NEW` the heap cannot satisfy leaves the
pointer `NIL`, and its first dereference is trap 4.

**Other ways a program ends.**

| What | Result |
|---|---|
| `HALT(n)` | exit status `n`, no message |
| The runtime module `Files` meets an error it cannot return: a file that cannot be made, a failed write or seek, a name too long | `-- <what>: <file>` on the standard error stream, exit status 99 |
| Integer `DIV` or `MOD` by zero, `MIN(T) DIV -1` | on x86, `SIGFPE` (status 136 in a shell), no message |
| A stack overflow: deep recursion, a frame or a value open-array parameter larger than the stack | `SIGSEGV` (status 139), no message |
| `SYSTEM.GET`, `PUT` or `MOVE` at an address that is not mapped | `SIGSEGV` (status 139) |

A program that ends normally, returning from its main module's body, has
exit status 0.

## 7. The command line

    poc [option]... <file>
    poc [option]... -build <file>
    poc [option]... -check <file>
    poc [option]... -compile <file>...
    poc [option]... -library <name> <file>...
    poc [option]... -install-library <name>
    poc [option]... -emit-interface <file>
    poc [option]... -show-interface <file>
    poc [option]... -emit-llvm-ir <file>
    poc [option]... -emit-macro32 <file>
    poc [option]... -version
    poc -help

Options come before the command. `-import-path`, `-library-path`, `-link`
and `-c-flag` add to what came before; of any other option given twice, the
later one wins.
`<file>` is a module's source; its name need not match the module's. poc
says nothing when a build, a library or a compilation succeeds, and writes
its errors, each `<file>:<line>:<column>: error: <what>`, then their
number, on the standard error stream.

### Commands

| Command | What it does |
|---|---|
| `<file>`, `-build <file>` | Builds a program: compiles `<file>`'s module and every module it imports that no library has, to `.sym`, `.ll` and `.o` files, and links them with the libraries into an executable named after the module, in the current directory (`-o` names another). |
| `-check <file>` | Checks the module against its imports' interfaces, writing nothing: "semantic OK" or the errors. Imports come from libraries and `.sym` files only, never compiled from source. The module is checked for the target a build would use: `-target`'s, else the host's. |
| `-compile <file>...` | Compiles each module to `.sym`, `.ll` and `.o`, and links nothing. |
| `-library <name> <file>...` | Builds the library `<name>` from the modules: section 8. |
| `-install-library <name>` | Copies the library `<name>`, found on the library path, into `<output-dir>/<triple>/<O2\|OC>/`, or without `-output-dir` into poc's own library directory. |
| `-emit-interface <file>` | Writes the module's interface, `<Module>.sym`. |
| `-show-interface <file>` | Prints the module's interface on the standard output. |
| `-emit-llvm-ir <file>` | Writes the module's LLVM IR, `<Module>.ll`. |
| `-emit-macro32 <file>` | Writes the module's VAX MACRO-32, `<Module>.mar`, and that of each module it imports compiled from source, for VAX/VMS; the module named is the program's main module, whose `.mar` has the program's start. Implies `-target vax-dec-vms`; takes `-O2` (the default) or `-OC`, under which `LONGINT` is a quadword. The VAX backend is being written: so far it writes a module's layout, its variables, assignments of integer, `CHAR`, `BOOLEAN` and `SET` expressions, fixed arrays and records without a base type, strings, the statements `IF`, `CASE`, `WHILE`, `REPEAT`, `FOR`, `LOOP`, `EXIT` and `RETURN`, procedures and calls of them, external `"VMS"` procedures, and the predeclared procedures `ABS`, `ODD`, `CHR`, `ORD`, `CAP`, `LEN`, `INC`, `DEC`, `INCL`, `EXCL`, `SHORT`, `LONG`, `ASH`, `COPY` and `HALT`, and imported variables and procedures, and reports anything more as a construct it cannot lower yet. |
| `-version` | Prints poc's version and the commit it was built from, the target and size model, and clang's version. |
| `-help`, `-h`, `--help` | Every command and option, on the standard output, with the commands for testing poc itself in a section of their own at the end. |
| `-print-import-path`, `-print-library-path` | Prints the import path or the library path, as the options before it leave it, one directory a line. |

`poc` with no arguments prints the same list on the standard error, and
fails. A command line poc cannot use - an unknown option, a command
without its file, or options with no file or command after them - gets
one line saying what is wrong, and a pointer to `-help`:

    $ poc -x
    poc: unknown option -x
    run poc -help for the commands and options

The commands for testing poc itself are `-dump-tokens`, `-check-syntax`,
`-dump-layout`, `-dump-llvm-types`, `-dump-nested`, `-dump-vax-types` and
`-dump-vax-names`.

### Options

| Option | Effect |
|---|---|
| `-o <exe>` | The executable's path. |
| `-O2`, `-OC` | The size model (section 1); `-O2` is the default. |
| `-import-path <dir>` | Adds `<dir>` to the directories searched for modules' sources and `.sym` files; repeatable. |
| `-clear-import-path` | Empties the import path, `POC_IMPORT_PATH`'s directories included. |
| `-library-path <dir>` | Adds `<dir>` to the directories searched for libraries, before `POC_LIBRARY_PATH`'s; repeatable. |
| `-clear-library-path` | Leaves out every library directory, `POC_LIBRARY_PATH`'s and poc's own included. |
| `-output-dir <dir>` | Writes `.sym`, `.ll` and `.o` files, and libraries, in `<dir>`, which is made if it is not there. |
| `-target <triple>` | Compiles for that LLVM target triple, as far as clang can (linking needs its C library). With `-emit-interface` or `-show-interface`, folds `SIZE`, `MAX` and `MIN` for its word size. `vax-dec-vms` is the VAX/VMS target, which takes `-emit-macro32`, `-check`, `-emit-interface`, `-show-interface`, `-build` and `-compile` so far. For it, `-build` writes every module's `.mar` and a DCL procedure, `<name>.com` (the main module's name, or `-o`'s without `.exe`), that assembles them on VMS and links them with poc's runtime, `POCRTL.OBJ` (assembled from `rtl/vax/PocRtl.mar`; taken from `POC$RTL:` when that logical name is defined), into `<NAME>.EXE`; every module must be compiled from source, including the runtime's `Out` (`-import-path rtl/vax`). `-compile` writes the named modules' `.mar` and a procedure, `<First>.com`, that assembles them. poc runs nothing on VMS itself: copy the files there and run the procedure (`@<NAME>`). |
| `-opt <level>` | clang's optimization level: `0`, `1`, `2`, `3`, `s`, `z` or `g`. The default is 2, and 0 for 32-bit x86. |
| `-g` | Debug information for gdb and lldb: procedures, lines, parameters, variables, records, arrays, pointers. Libraries are looked for first in their `-g` copies (section 8). Best with `-opt 0` or `-opt g`. |
| `-trap-location` | A trap's message names its file, line, column and procedure (section 6). |
| `-trap-heap-exhausted` | A `NEW` the heap cannot satisfy is trap 11, not a `NIL` pointer. |
| `-range-checks` | `SHORT` of an integer and `CHR` of a value that does not fit are trap 14. |
| `-strict` | The module named may use only `Oberon2.pdf`'s language (section 3). |
| `-static` | Links a fully static executable. |
| `-shared-libraries` | Links the libraries' shared objects, not their archives. |
| `-link <arg>` | Passes `<arg>` to the link (`-lz`, `-L<dir>`); repeatable. With `-library`, also recorded in the manifest, for every program that links the library. |
| `-c-flag <arg>` | Passes `<arg>` to clang when it compiles a module's C part, `<Module>.c` beside `<Module>.Mod`, or clang++ its C++ part, `<Module>.cpp` (`-I<dir>`, `-D<name>`); repeatable. |
| `-lto` | Compiles to LLVM bitcode and optimizes the whole program when it is linked. On NetBSD it needs lld (pkgsrc's `lld`). Ignored for 32-bit x86 NetBSD unless poc runs on 32-bit x86 NetBSD. |
| `-rebuild` | Compiles every module's object again, reusing none (section 8). |
| `-verbose` | Prints each command poc runs (clang's). |

`doc/developer/voc-options.md` lists voc's options and what each is in poc.

### Where modules come from

A module an `IMPORT` names is taken, in order: from a library on the
library path; from `<Module>.Mod` or `<Module>.mod` in the current
directory, then in each directory of the import path; from `<Module>.sym`
with `<Module>.o` (or `<Module>.ll`), searched the same way. `SYSTEM` is
built in. A program in which any module uses `NEW`, or that has a module
from a library, also gets the collector, `GarbageCollectedHeap` and
`ModuleTable`, from `poc-rtl`. When an import is found in none of these,
the error's notes say where poc looked, and name each library on the
library path that has the module for the other size model or for another
target.

### Environment

| Variable | Use |
|---|---|
| `POC_IMPORT_PATH` | Directories, separated by colons, that start the import path; `-import-path` adds after them. |
| `POC_LIBRARY_PATH` | Directories, separated by colons, searched for libraries after `-library-path`'s and before poc's own. |
| `PATH` | Where poc finds `clang`, and the shell finds what `-verbose` shows. |

poc's own library directory is `<directory of poc>/../lib/poc`, found
through the path poc was started by, a symbolic link followed.

### Exit status

poc exits with status 0 when it did what it was asked, and 1 when it
reported an error, or its arguments were wrong.

## 8. Files and formats

**What a build writes.** For each module it compiles, in the current
directory or `-output-dir`: `<Module>.sym`, the interface; `<Module>.ll`,
the LLVM IR; `<Module>.o`, the object; and `<Module>.c.o` for a module with
a C part, `<Module>.cpp.o` for one with a C++ part (a module may not have
both). With `-lto`, the `.o` holds LLVM bitcode. A program or shared library
with a C++ part, its own or a library's, is linked by clang++, not clang.

**Objects reused.** Each module from source is checked and turned into IR
on every build, but its object is compiled only when it would differ from
the one there. `<Module>.ll` ends with a symbol `@<Module>.-build.<stamp>`,
where `<stamp>` is the 64-bit FNV-1a hash of the `clang -c` command and the
IR; when `<Module>.o` already defines it, it is linked as it is. A C or C++
part is compiled with `-MD`, which writes `<Module>.c.o.d` (or
`<Module>.cpp.o.d`), the files it read; poc adds a line `# poc-build
<stamp>`, the hash of the command and of every one of those files, and
reuses the object while they hash the same. So an object is compiled again
when its source, a header, an imported interface, or an option that
changes its IR or command (`-opt`, `-g`, `-O2`/`-OC`, `-target`, `-c-flag`)
changes, and not because a file's time did. Under `-lto`, for a module
given as its `.sym` and `.ll`, and in `-library`, which leaves no stamps,
nothing is reused; `-rebuild` reuses nothing.

**Objects and keys.** Each module's object defines a symbol
`<Module>.-key.<O2|OC>.<key>`, where `<key>` is 16 hexadecimal digits, the
64-bit FNV-1a hash of its `.sym` file, and `<Module>.-target.<triple>`;
it refers to the key of each module it imports. So a program links only if
every module was compiled against the interfaces its imports have now: a
link that fails on an undefined `...-key...` symbol means a module must be
compiled again.

**The `.sym` file** is the module's interface as Oberon text: a definition
of the module, which `-show-interface` prints. It has the module's imports,
then its exported constants, types and variables, and its exported
procedures as forward declarations (`PROCEDURE^`). A constant appears with
its value, a record or array constant as its literal with every field
given, in a second `CONST` section after the types. A record type appears
with all its fields, the hidden ones without an export mark, and so do the
unexported types they need, since an importer must know the record's layout;
a module cannot name them. A field with a default has the default's value
after it, `:= 1`, or `:= ..` when it is not a constant (section 3). The text is poc's to
write, and a module cannot be written in it: it describes a compiled
module, whose code is in the `.o`.

```
MODULE Args;
  IMPORT Modules, Platform, SYSTEM;
  VAR
    argc-: INTEGER;
    argv-: SYSTEM.ADDRESS;
  PROCEDURE^ Get*(n: INTEGER; VAR val: ARRAY OF CHAR);
  PROCEDURE^ GetInt*(n: INTEGER; VAR val: LONGINT);
  PROCEDURE^ Pos*(s: ARRAY OF CHAR): INTEGER;
  PROCEDURE^ GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
  PROCEDURE^ getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
END Args.
```

**A library** is a set of modules compiled for one target and size model,
in a directory `<base>/<triple>/<O2|OC>/` (with `-g`, `<O2|OC>-g/`), where
`<base>` is `-output-dir`, or a directory of the library path. There are:

- `lib<name>.a` and the shared object `lib<name>.so`;
- each module's `<Module>.sym`, `.ll` and `.o`;
- `<Module>.owner` for each module, holding the library's name: a module
  belongs to one library;
- `<name>.library`, the manifest.

The manifest is text, one fact a line, words separated by a space:

| Line | Meaning |
|---|---|
| `library <name>` | the library's name |
| `poc <version>` | the poc that built it; another version refuses the library ("rebuild it") |
| `triple <triple>` | the target |
| `model <O2\|OC>` | the size model |
| `lto` | its objects are LLVM bitcode |
| `needs <library>` | a library its modules import from, one line each |
| `c++` | a module of it has a C++ part, so clang++ links a program that uses it |
| `link <arg>` | each `-link <arg>` it was built with, the rest of the line; a program that links it, directly or through `needs`, gets each one, once, after the libraries and before its own `-link` arguments |
| `module <Module> <key>` | each module and its key |
| `import <Module> <Imported> <key>` | each import of each module, with the key it was compiled against |
| `source <Module> <key>` | the hash of each module's source file |

The library path is searched in order: `-library-path`'s directories,
`POC_LIBRARY_PATH`'s, then poc's own; the first directory whose
`<triple>/<O2|OC>/` has `<Module>.owner` has the module, and poc warns of
any later one that has it too. Before linking, poc checks that the keys of
all the libraries a program uses agree.

**Installed files.** `make install` puts `poc` in `$(BINDIR)`, the runtime
library `poc-rtl` for the host in `$(LIBDIR)/poc/<triple>/{O2,OC,O2-g,OC-g}/`,
`poc.1` in `$(MANDIR)/man1`, and the guides in `$(DOCDIR)`.

## 9. The runtime modules

The library `poc-rtl` has the modules a program may import, with voc's
interfaces so that a program written for voc compiles unchanged, poc's own
`Err`, `OutStr` and `InStr`, and six that are poc's own machinery, which a
program does not import itself: `FileDescriptorOutput`, `FormattedInput`,
`FormattedOutput`, `FormattedText`, `ModuleTable` and `RealDigits`. `SYSTEM` is built into the compiler (section 4).

For each module: its description, including where it differs from voc's,
then its interface as `poc -show-interface` prints it, each declaration
with its comment from the source. This chapter is generated from
`rtl/llvm` by `tools/rtl-reference`, and the test suite checks that it is
up to date.

<!-- rtl-reference begin -->
<!-- Generated by tools/rtl-reference from rtl/llvm; edit the modules, then run it with update. -->

### Args

```text
voc's Args module (src/library/v4/Args.Mod, Ofront's, after Oberon
V4's) with its whole interface: the command line and the environment,
for programs written for it. Each procedure is Modules' or Platform's
of the same meaning under V4's names, as in voc, so the two always
agree.

Arguments are numbered as in C (Modules.Mod, "THE COMMAND LINE"): 0
is the program's own name as it was started, 1 the first argument,
argc the number of them all. argv is the address of C's argv, an
array of argc strings' addresses.

getEnv is voc's Platform.getEnv (src/runtime/Platformunix.Mod), which
voc's Args passes on: it says whether the variable is there at all,
so a program can tell an empty value from none; GetEnv cannot.

Where this differs from voc's, it is where Modules and Platform do
(the numbers are those of vishap-bugs, ~/Repos/Oberon/vishap-bugs):
- Get with n outside 0..argc-1 sets val to "" (D11);
- getEnv returns FALSE for a name with no 0X in it.
```

```oberon
MODULE Args;
  VAR
    (* the number of arguments, the program's name included, and C's argv *)
    argc-: INTEGER;
    argv-: SYSTEM.ADDRESS;

  (* Argument n in val, cut short if val is too small for it *)
  PROCEDURE Get*(n: INTEGER; VAR val: ARRAY OF CHAR);

  (* Argument n as a number - an optional minus sign and decimal digits;
     val is left alone if it does not start with a digit (after the sign) *)
  PROCEDURE GetInt*(n: INTEGER; VAR val: LONGINT);

  (* The number of the first argument (from 0) equal to s, argc if none is *)
  PROCEDURE Pos*(s: ARRAY OF CHAR): INTEGER;

  (* The value of the environment variable var in val, cut short if val is
     too small for it; "" when there is no such variable (or it is empty) *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);

  (* The value of the environment variable var in val, cut short if val is
     too small for it; FALSE, and val unchanged, when there is no such
     variable *)
  PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
END Args.
```

### Console

```text
minimal, always-available text output to the
standard output descriptor, the same interface voc's own Console.Mod
offers (Flush, Char, String, Int, Ln, Bool, Hex - so a program using
only those runs unchanged under both compilers, and a fixture can be
cross-checked against voc), written as ordinary Oberon-2 over one
external write(2).

Unlike voc's, nothing is buffered: every call writes what it was
given before it returns, so no output is lost when a program ends
without a Flush or is stopped by a trap, and it interleaves correctly
with anything else writing to descriptor 1 (the run-time traps, or a
module that declares its own write(2)). Flush is therefore empty, kept
so existing voc programs still compile. A call writes as few times as
it can: String and Hex once, Int once (twice when padding), Char and
Ln once each.

write(2) is declared with the shape the other fixtures and the trap
support already give it (the backend declares a C symbol once per
program, whichever module names it first): no result, since the
trap support calls it that way too. So a short or failed write is not
noticed - on a blocking descriptor that takes a signal arriving
mid-write, and nothing here could do more than give up on failure
anyway. The byte count is SYSTEM.ADDRESS, as wide as size_t on the
target, so the call is right on a 32-bit target too. The newline is
0AX on Linux and on NetBSD, OpenBSD and FreeBSD alike.
```

```oberon
MODULE Console;
  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*();
  PROCEDURE Char*(ch: CHAR);

  (* The characters of s up to its terminating 0X, or all of s if it has
     none. *)
  PROCEDURE String*(s: ARRAY OF CHAR);
  PROCEDURE Ln*();
  PROCEDURE Bool*(b: BOOLEAN);

  (* i in decimal, right-aligned in a field n characters wide (a shorter
     number is padded with blanks on the left, a longer one is not
     truncated). Takes a HUGEINT so every integer type widens to it; voc's
     takes SYSTEM.INT64, which poc has too, HUGEINT's equal. The smallest HUGEINT
     has no positive counterpart to print digit by digit, so it is written
     out whole. *)
  PROCEDURE Int*(i: HUGEINT; n: LONGINT);

  (* i as hexadecimal digits, all of them: two per byte of a LONGINT (8 for
     the 4-byte LONGINT of the -O2 size model), most significant first,
     upper case, so a negative number shows its two's complement. *)
  PROCEDURE Hex*(i: LONGINT);
END Console.
```

### Err

```text
Phase 11 A26: Out's interface - Open, Flush, Char, String, Int, Hex,
Ln, Real, LongReal, Ten and IsConsole - writing to the standard error
stream (descriptor 2) instead of standard output, for messages that
must not mix with a program's output when it is redirected. voc has no
such module; the names and what each procedure prints are Out's (see
Out.Mod), and both write through FormattedOutput.

Unbuffered, as C's stderr is: every call has written its output when
it returns, so nothing is lost when a program ends without a Ln or is
stopped by a trap, and on a terminal Err and Out appear in the order of
the calls. Flush and Open do nothing. IsConsole says whether standard
error is a terminal.
```

```oberon
MODULE Err;
  VAR
    (* whether the stream is a terminal *)
    IsConsole-: BOOLEAN;

  (* Initializes the error stream; there is nothing to do. *)
  PROCEDURE Open*();

  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*();
  PROCEDURE Char*(ch: CHAR);

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  PROCEDURE Ln*();

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x: HUGEINT; n: HUGEINT);

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x: HUGEINT; n: HUGEINT);

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER);

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
END Err.
```

### FileDescriptorOutput (poc's own)

```text
Phase 11 D11: the two operating-system calls FormattedOutput, Out and
Err make - writing bytes to a descriptor and asking whether it is a
terminal - kept apart so that FormattedOutput, Err and RealDigits are
one source that both poc and voc compile. This is poc's version, over
write(2) and isatty(3), the same on Linux, NetBSD, OpenBSD and FreeBSD;
rtl/voc/FileDescriptorOutput.Mod is voc's, over its Platform module,
for Stage 0 (tools/bootstrap/stage0).

write(2) is declared with Console's shape (the backend declares a C
symbol once per program, whichever module names it first), with no
result: a short or failed write is not noticed, as in Console.
```

```oberon
MODULE FileDescriptorOutput;
  CONST
    (* the descriptors of standard output and standard error *)
    standardOutput* = 1;
    standardError* = 2;

  (* count bytes from buffer to descriptor *)
  PROCEDURE Write*(descriptor: SYSTEM.INT32; buffer: SYSTEM.ADDRESS; count: SYSTEM.ADDRESS);

  (* Whether descriptor is a terminal. *)
  PROCEDURE IsTerminal*(descriptor: SYSTEM.INT32): BOOLEAN;
END FileDescriptorOutput.
```

### Files

```text
Oberon files - the
Oakwood Guidelines' Files module with voc's interface (src/runtime/
Files.Mod): File and Rider, New, Old, Register, Close, Purge, Length,
GetDate, GetName, Set, Pos, Base, Read, ReadByte, ReadBytes, Write,
WriteBytes, the typed riders (Read/Write Bool, Int, LInt, Set, Real,
LReal, String, Num, and ReadLine), Delete, Rename, ChangeDirectory,
SetSearchPath, MaxNameLength and MaxPathLength. Read, Write and
ReadByte take a SYSTEM.BYTE, so a CHAR, a BOOLEAN or a one-byte
SHORTINT variable can be read into (AGENTS.md, "SYSTEM subset").

THE EXTERNAL FORMAT of the typed riders is Oakwood's (1.2.5.4), under
both size models: little-endian, an INTEGER 2 bytes, a LONGINT 4, a
SET 4 (element 0 the least significant bit), a BOOLEAN 1 (0 or 1), a
REAL and a LONGREAL their IEEE 4 and 8 bytes, a string up to its 0X
and the 0X. So a file written under -O2 reads back under -OC and with
voc. Under -OC an INTEGER or a LONGINT wider than its format loses
its high bytes on the way out, as voc's does; a value read back is
sign-extended, where voc's -OC reads a negative one as a large
positive one (decided with the user 2026-10-02). WriteNum and
ReadNum are voc's variable-length numbers: seven bits a byte, the
last byte's top bit clear and its bit 6 the sign.

THE MODEL. A File is a byte sequence with a length; a Rider is a
position in one (r.position, set by Set) and the result of the last
operation (r.eof, r.res). Set clamps a position into 0..Length, so a
file has no holes; Write at the end extends the file, Write inside it
overwrites. Several riders may share a file and see each other's
writes at once.

A File does not keep its own buffers: it holds a C stdio stream, and
libc does the buffering. Every operation says where it means to
work, and the file seeks when the stream is somewhere else or was last
used the other way (C requires a seek between a read and a write).
stdio is what makes this portable. open(2) and lseek(2) are not the
same on Linux and the three BSDs: O_CREAT and O_TRUNC have different
values, and lseek's off_t is 32 bits on 32-bit Linux but 64 on 32-bit
NetBSD, OpenBSD and FreeBSD (the BSD half from memory, to be confirmed
on those systems), with no conditional compilation to choose between
them. fopen takes a mode *string*, and fseek a `long`, which
is a word on every one of them - so a file is limited to what a
LONGINT holds (2 GB under the -O2 size model), as in voc.

NEW AND REGISTER. New creates nothing on disk. The first write (or
Close, or Register) creates a temporary file in the directory of the
name given to New - ".tmp.<n>.<pid>", so it cannot collide with a
real file - and Register renames it to that name, replacing any file
already there in one step: a reader never sees a half-written result,
and a compiler that stops half way leaves the old file. Every name is
made absolute when it is given (from Platform.CWD), so a program that
changes directory between New and Register still registers where it
meant to.

OPEN STREAMS AND FINALIZATION. Close writes everything out and closes
the stream, but the File stays usable: the next operation reopens it.
Every File is registered with the collector (GarbageCollectedHeap.
RegisterFinalizer, Phase 12 step 5c), as voc's are: when one is no
longer reachable, or the program ends, its stream is closed, its data
written, and the temporary file of a New file never registered is
deleted.

OLD AND THE SEARCH PATH. A name with a "/" in it is looked for where
it says. Any other is looked for in each directory of the search path
in turn, which is just the current directory until SetSearchPath
sets one: directories separated by ";", blanks around them ignored, a
leading "~" standing for $HOME, as voc's.

Where this differs from voc's, besides the missing procedures (the
numbers are those of vishap-bugs, ~/Repos/Oberon/vishap-bugs):
- GetName of a new File is its temporary file's absolute path (D16);
- two Old calls for one file give two independent Files (D14); after a
  Register over a file that another File has open, that File keeps
  reading the old contents;
- ReadString and ReadLine cut a value too long for the array short,
  and ReadLine skips the rest of the line (23);
- an error that cannot be reported to the caller - a file that cannot
  be created, a failed write - stops the program with a message and
  Halt(99), as voc does, but on standard error (D12; Phase 11 D12).
```

```oberon
MODULE Files;
  TYPE
    (* a file, open or registered under a name *)
    File* = POINTER TO FileDesc;

    (* a position in a file to read or write at, with the result of the last
       operation *)
    Rider* = RECORD res*: LONGINT; eof*: BOOLEAN END;
  VAR
    (* the longest path and file name the system takes (Platform's) *)
    MaxPathLength-: INTEGER;
    MaxNameLength-: INTEGER;

  (* A new, empty file, to be called name once registered (NEW AND
     REGISTER above); nothing is made on disk until it is written to,
     closed or registered. *)
  PROCEDURE New*(name: ARRAY OF CHAR): File;

  (* The file called name, or NIL if there is none or it cannot be opened
     (OLD AND THE SEARCH PATH above). It is opened for reading and writing
     if the system allows, else for reading only. *)
  PROCEDURE Old*(name: ARRAY OF CHAR): File;

  (* Writes out what is buffered and closes the stream; f can still be
     used, reopening itself. A New file that was never written to is
     created, empty. *)
  PROCEDURE Close*(f: File);

  (* Closes f, and if it came from New gives it its name (replacing any
     file already there). *)
  PROCEDURE Register*(f: File);

  (* The number of bytes in f. *)
  PROCEDURE Length*(f: File): LONGINT;

  (* Empties f: its length is 0. *)
  PROCEDURE Purge*(f: File);

  (* The time and date f was last changed, in Oberon's clock format
     (Platform.GetClock): t = hour * 4096 + minute * 64 + second, d =
     year MOD 100 * 512 + month * 32 + day, month 1..12. A New file not yet written to
     is created first, as voc's. *)
  PROCEDURE GetDate*(f: File; VAR t: LONGINT; VAR d: LONGINT);

  (* The name f was asked for by (Old) or registered under (New and
     Register); a New file not registered yet: its temporary file, "" if
     it has none yet. *)
  PROCEDURE GetName*(f: File; VAR name: ARRAY OF CHAR);

  (* Points r at position pos of f (0 if it is negative, the end if it is
     past the end) and clears its eof and res. *)
  PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);

  (* r's position in its file. *)
  PROCEDURE Pos*(VAR r: Rider): LONGINT;

  (* The file r is on. *)
  PROCEDURE Base*(VAR r: Rider): File;

  (* The byte at r's position, and on to the next. At the end of the file x
     is 0X and r.eof is set. *)
  PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);

  (* x at r's position, overwriting the byte there or, at the end,
     extending the file, and on to the next. *)
  PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);

  (* Read, by the name Project Oberon's Files has *)
  PROCEDURE ReadByte*(VAR r: Rider; VAR x: SYSTEM.BYTE);

  (* n bytes into x from its start; r.res is how many of them were not
     there to read, and r.eof is set if any. n larger than x traps (index
     out of range), as voc's does. *)
  PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);

  (* The first n bytes of x; n larger than x traps, as in ReadBytes. *)
  PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);

  (* The characters of x up to and including its 0X (all of x if it has
     none) - the terminator is written, as voc does, so that ReadString
     finds where the string ends. *)
  PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);

  (* Reads up to the next 0X (or the end of the file) into x, cutting it
     short if x cannot hold it all. *)
  PROCEDURE ReadString*(VAR r: Rider; VAR x: ARRAY OF CHAR);

  (* Reads up to the next line feed (or 0X, or the end of the file) into
     x, without the line feed or a carriage return before it; a line too
     long for x is cut short. At the end of the file r.eof is set, so a
     last line with no line feed after it is returned with r.eof set. *)
  PROCEDURE ReadLine*(VAR r: Rider; VAR x: ARRAY OF CHAR);

  (* Deletes the file called name; res is 0 if it did, else the error
     code (Platform.ErrorCode). *)
  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);

  (* Renames the file old to new, replacing a file of that name; res is 0
     if it did, else the error code (Platform.ErrorCode). *)
  PROCEDURE Rename*(old: ARRAY OF CHAR; new: ARRAY OF CHAR; VAR res: INTEGER);

  (* Makes path the current directory; res is 0 if it did, else the error
     code. A relative name given to Old or New after it is taken from
     there. *)
  PROCEDURE ChangeDirectory*(path: ARRAY OF CHAR; VAR res: INTEGER);

  (* The directories Old looks in for a name without a "/" (OLD AND THE
     SEARCH PATH above); "" for just the current directory again. *)
  PROCEDURE SetSearchPath*(path: ARRAY OF CHAR);

  (* The typed riders: a value in the external format (THE EXTERNAL
     FORMAT above) at r's position, and on past it; at the end of the file
     r.eof is set, as by Read. *)
  PROCEDURE ReadBool*(VAR r: Rider; VAR x: BOOLEAN);
  PROCEDURE ReadInt*(VAR r: Rider; VAR x: INTEGER);
  PROCEDURE ReadLInt*(VAR r: Rider; VAR x: LONGINT);
  PROCEDURE ReadSet*(VAR r: Rider; VAR x: SET);
  PROCEDURE ReadReal*(VAR r: Rider; VAR x: REAL);
  PROCEDURE ReadLReal*(VAR r: Rider; VAR x: LONGREAL);

  (* A number WriteNum wrote, into x, which may be any integer variable of
     at most 8 bytes: its low bytes, as voc's. *)
  PROCEDURE ReadNum*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE);

  (* The typed riders: x in the external format (THE EXTERNAL FORMAT
     above) at r's position, and on past it. *)
  PROCEDURE WriteBool*(VAR r: Rider; x: BOOLEAN);
  PROCEDURE WriteInt*(VAR r: Rider; x: INTEGER);
  PROCEDURE WriteLInt*(VAR r: Rider; x: LONGINT);
  PROCEDURE WriteSet*(VAR r: Rider; x: SET);
  PROCEDURE WriteReal*(VAR r: Rider; x: REAL);
  PROCEDURE WriteLReal*(VAR r: Rider; x: LONGREAL);

  (* x as a variable-length number (THE EXTERNAL FORMAT above), which
     ReadNum reads back. *)
  PROCEDURE WriteNum*(VAR r: Rider; x: SYSTEM.INT64);
END Files.
```

### FormattedInput (poc's own)

```text
The tokens In reads from standard input and InStr from a string
(Phase 15's "Ongoing library enhancements" 2), recognized here once, over
a Source of characters, so that the two cannot come to accept
different text. Internal, like FormattedText: a program imports In or
InStr. In.Mod describes each token and how it differs from voc's.

Each procedure returns whether it found what it was asked for, and
leaves its argument as In does when it did not. It reads only as far as
it must: the character after a number or a word is looked at, not used
up.

A Source is the characters still to be read: Ready says whether there
is one, Current which it is, and Advance moves past it. In's reads
standard input (In.Mod); StringSource, below, reads a string in place.
Neither In nor InStr is compiled by voc, so this module may use what
poc alone has.
```

```oberon
MODULE FormattedInput;
  CONST
    (* the longest number Real and LongReal will read *)
    maxNumber* = 64;
  TYPE
    (* abstract: each method is an extension's *)
    Source* = RECORD  END;

    (* the characters of a string from a position on, read through its
       address: a string ends at its first 0X or at its length *)
    StringSource* = RECORD (Source) position*: LONGINT END;

  (* whether there is a character to read *)
  PROCEDURE (VAR self: Source) Ready*(): BOOLEAN;

  (* the character to read; 0X if there is none *)
  PROCEDURE (VAR self: Source) Current*(): CHAR;

  (* moves past the character to read *)
  PROCEDURE (VAR self: Source) Advance*();

  (* whether there is a character to read *)
  PROCEDURE (VAR self: StringSource) Ready*(): BOOLEAN;

  (* the character to read; 0X if there is none *)
  PROCEDURE (VAR self: StringSource) Current*(): CHAR;

  (* moves past the character to read *)
  PROCEDURE (VAR self: StringSource) Advance*();

  (* Makes source read s, of length LEN(s), from position on: s ends at its
     first 0X, or at LEN(s) if it has none. s is read where it is, so it
     must stay in place, unchanged, while source is used. *)
  PROCEDURE OpenString*(VAR source: StringSource; address: SYSTEM.ADDRESS; length: LONGINT; position: LONGINT);

  (* whether position is within the string, its end included *)
  PROCEDURE InString*(VAR source: StringSource): BOOLEAN;

  (* past any blanks, tabs and line ends (any character up to " ") *)
  PROCEDURE Skip*(VAR source: Source);

  (* The next character, line end (0AX) included; ch is 0X if there is
     none. *)
  PROCEDURE Char*(VAR source: Source; VAR ch: CHAR): BOOLEAN;

  (* An integer, after any blanks: an optional minus sign, then decimal
     digits, or hexadecimal digits (0-9, A-F) and an H. h is left alone if
     there is nothing to read, and is 0 if what there is is not a
     number. *)
  PROCEDURE HugeInt*(VAR source: Source; VAR h: HUGEINT): BOOLEAN;

  (* The rest of the line - up to a line feed, and without the carriage
     return before it - cut short if line cannot hold it all (the rest is
     then left for the next read). FALSE if there is nothing to read. *)
  PROCEDURE Line*(VAR source: Source; VAR line: ARRAY OF CHAR): BOOLEAN;

  (* A string in double quotes, on one line, without the quotes, after any
     blanks; str is "" if there is none. *)
  PROCEDURE String*(VAR source: Source; VAR str: ARRAY OF CHAR): BOOLEAN;

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR source: Source; VAR name: ARRAY OF CHAR): BOOLEAN;

  (* A real number (Numeral), correctly rounded by the C library's strtof;
     x is left alone if it is not one. *)
  PROCEDURE Real*(VAR source: Source; VAR x: REAL): BOOLEAN;

  (* The same, by strtod *)
  PROCEDURE LongReal*(VAR source: Source; VAR x: LONGREAL): BOOLEAN;

  (* whether nothing but blanks and tabs is left to read *)
  PROCEDURE OnlyBlanksLeft*(VAR source: Source): BOOLEAN;
END FormattedInput.
```

### FormattedOutput (poc's own)

```text
Phase 11 A26: the formatting behind Out (standard output) and Err
(standard error), written once, with the descriptor to write to as
every procedure's first parameter. Internal, like RealDigits: a program
imports Out or Err. What each procedure prints, and how that differs
from voc's Out, is described in Out.Mod; Int is Console.Int's. The
text of each number is FormattedText's, which OutStr appends to a
string (Phase 15's "Ongoing library enhancements" 1); this module pads
it to its field and writes it.

Nothing is buffered: every call has written its output when it returns,
so Out, Err, Console and the trap messages come out in the order of the
calls, and nothing is lost when a program ends without a Ln or is
stopped by a trap. The writing itself is FileDescriptorOutput's (Phase
11 D11), so that voc compiles this module too, over its own version of
that one (rtl/voc), for Stage 0's Err.
```

```oberon
MODULE FormattedOutput;
  (* ch *)
  PROCEDURE Char*(descriptor: SYSTEM.INT32; ch: CHAR);

  (* The characters of s up to its 0X (all of it if it has none), without
     the 0X, in one write. *)
  PROCEDURE String*(descriptor: SYSTEM.INT32; s: ARRAY OF CHAR);
  PROCEDURE Ln*(descriptor: SYSTEM.INT32);

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. A negative n is taken as 0. *)
  PROCEDURE Int*(descriptor: SYSTEM.INT32; x: HUGEINT; n: HUGEINT);

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(descriptor: SYSTEM.INT32; x: HUGEINT; n: HUGEINT);

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(descriptor: SYSTEM.INT32; x: REAL; n: INTEGER);

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(descriptor: SYSTEM.INT32; x: LONGREAL; n: INTEGER);
END FormattedOutput.
```

### FormattedText (poc's own)

```text
The text of each number Out writes, without the blanks that pad it to
its field: what FormattedOutput writes (for Out and Err) and OutStr
appends to a string (Phase 15's "Ongoing library enhancements" 1), made
here once so that the two cannot drift apart. Internal, like
RealDigits: a program imports Out, Err or OutStr. What each procedure
makes, and how that differs from voc's Out, is described in Out.Mod.

Int, Real and LongReal are right-aligned in a field of n characters:
the caller pads with n - Length(text) blanks, nothing if that is not
positive. Hex has no field, only a digit count.

voc compiles this module for Stage 0 (Phase 11 D11), as it does
FormattedOutput, so it must stay within what voc accepts.
```

```oberon
MODULE FormattedText;
  CONST
    (* the room every text below needs, its 0X included *)
    maxText* = 32;

  (* The characters of text before its first 0X (all of it if it has
     none) *)
  PROCEDURE Length*(VAR text: ARRAY OF CHAR): LONGINT;

  (* x in decimal, with a minus sign if it is negative, and no plus sign.
     The smallest HUGEINT has no positive counterpart to make digit by
     digit, so it is written out whole. *)
  PROCEDURE Int*(x: HUGEINT; VAR text: ARRAY OF CHAR);

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x: HUGEINT; n: HUGEINT; VAR text: ARRAY OF CHAR);

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;

  (* x in exponential form (d.dddE+dd), with as many digits as fit a field
     of n characters, from 2 to 9, at least 6 generated to drop trailing
     zeros from. A plus sign of the mantissa is not written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER; VAR text: ARRAY OF CHAR);

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER; VAR text: ARRAY OF CHAR);
END FormattedText.
```

### GarbageCollectedHeap

```text
the bespoke mark-sweep collector every
LLVM-targeted program that allocates on the heap links in. Written
as ordinary Oberon-2 over SYSTEM.ADDRESS - no pointer variables, no
NEW - so it can be compiled by poc itself, and depends on the C
library only for calloc (chunk memory) and LLVM's own
llvm.eh.unwind.init (register spilling).

HEAP SHAPE. Memory comes from calloc in *chunks*. A chunk holds, in
order: a small header (the ChunkNext.. words below), a *start map* -
one byte per 16-byte granule of the block area, non-zero where a
block starts - and the block area itself. Blocks are whole multiples
of the 16-byte granule:

  block + 0           header word: size * 4 + inUse * 2 + marked,
                      where size is the object's data size in bytes
                      for an allocated block, the whole block's
                      size in bytes for a free one
  block + word        the tag word: 0, or the address of a type
                      descriptor (LLVMCodeGenerator.Mod's "tag" -
                      see the section on run-time type descriptors
                      there for the layout this file reads)
  block + 2 * word    the object's data; Allocate returns this
                      address, so an object's tag sits at
                      address - word, where the report's own
                      v^.tag expects it

A free block reuses its first two words for the header and a link to
the next free block. The block area of a chunk is used from the
bottom (a *bump pointer* moves up as fresh blocks are cut), and swept
memory goes onto free lists, which are tried before the bump pointers.

FREE LISTS (Phase 11 D15, 2026-09-26). One list for each block size up to
smallBlockBytes (16, 32, .. 512 bytes: the size classes), every block
on it exactly that size, and one list of every bigger block. A request
takes the head of its own class's list; if that is empty, it splits
the first block of the next larger class that has one, or else the
first block of the big list that is large enough, and the rest of the
block goes onto the list of its own size. Until then all free memory
was on one address-ordered list searched first-fit, whose walk past
blocks too small for the request was 20-30% of the Stage 1 poc's time
compiling itself, and grew with any change in the mix of sizes it
allocated.

TRACING. What a live object's outgoing pointers are comes from its
tag: a descriptor's `size` (one element's bytes), `ptrCount` and
pointer-offset table. An object may be several elements of that
description end to end (an array of records) - the block's data size
divided by `size` is the element count. A tag of 0 marks an object
with no pointers in it. Module-level pointer variables come from the
per-module root tables registered in ModuleTable. And - since poc has
no stack maps - the machine stack is scanned *conservatively*: any
word on it that points anywhere into an allocated block, interior
included, keeps that block alive. The registers are spilled into the
collector's own frame first (llvm.eh.unwind.init). The base of the
stack is what the program's `main` reports through SetStackBase, so
a program whose `main` does not is scanned by roots only.

Marking uses an explicit mark stack (a calloc'd array, so a long list
cannot overflow the machine stack). If even that overflows, marking
falls back to re-tracing every marked block until a pass overflows
nothing - slow, but exact.

THE POLICY. A collection runs when neither the free list nor a bump
pointer can supply a request. If it leaves less than half of the
block area free, the heap grows by one chunk big enough to make the
block area twice the live data (GrowAfterCollection); if the request
is still unsatisfied, by a chunk that holds it - either up to a
ceiling (SetHeapLimit), and Allocate answers 0 only when the ceiling
stops it. So the heap grows geometrically, and between two
collections the program allocates at least as much as survived the
first one: the tracing, which costs in proportion to the live data,
is paid for by that allocation. Until 2026-09-26 (Phase 11 D14) the
heap grew by one default chunk whenever a collection left under a
quarter free, so a program whose live data kept growing was traced
once for every 256 KB it grew - 172 full collections for the Stage 1
poc compiling itself, 69% of their time spent tracing. Nothing moves,
and chunks are never given back.

FINDING A CHUNK. Every word the marker looks at - each conservative
stack word and each pointer a traced block holds - needs the chunk it
lies in (ChunkOf). The chunks are also kept in a table ordered by
address and binary-searched (Phase 11 A15, 2026-09-25): until then
ChunkOf walked the chunk list, and in the Stage 1 poc compiling
itself that walk was 87% of all the instructions it ran. Chunks never
move or overlap, and the table only grows, when a chunk is added.
The search orders addresses as unsigned numbers: SYSTEM.ADDRESS is
signed, so each address is first turned into a key by adding
MIN(SYSTEM.ADDRESS), which flips its top bit (the addition wraps) and
so maps unsigned order onto signed order. Ordered as signed numbers, a
chunk straddling the middle of a 32-bit address space - which OpenBSD
i386's calloc can hand out - would have its upper part missed, and the
objects there freed while still in use.

FINALIZATION (PLAN.md Phase 12 step 5c, from voc's Heap; decided with
the user 2026-10-02). RegisterFinalizer(obj, finalize) has finalize
called with obj once obj can no longer be reached, after the
collection that finds it so. The table of registered objects is
calloc'd memory, which nothing scans, so it does not keep them
alive. After marking, every registered object left unmarked moves to
the pending table, and then the pending objects are marked as roots
are, with everything they reach: their memory, and what a finalizer
may still read through them, survives the sweep. Each finalizer is
taken off the pending table before it is called, after the
collection has finished, so it may allocate, collect, register
again, or store obj where it is reachable again (it is not called a
second time). The objects found unreachable by one collection are
finalized newest registered first, as voc's are.

And when the program ends, by returning from its main module's
body, HALT, ASSERT, a trap or Platform.Exit, every object still
registered or pending is finalized, newest first, reachable or not:
the first registration hands FinalizeAtExit to the C library's
atexit, and every one of those ends with exit(). voc runs them at the
same points, except Platform.Exit, and before a trap's message
rather than after it (vishap-bugs D13). A program killed by a
signal (SIGFPE, a division by zero on x86; SIGSEGV) runs none. A
finalizer that traps while the program is ending calls exit() a
second time, which C leaves undefined; the C libraries of the four
systems run the remaining handlers.

LIMITS worth knowing. One object may not exceed maxObjectSize bytes. A pointer the compiler has shifted, masked or
split is invisible to a conservative scan; poc's own output never
does that.
```

```oberon
MODULE GarbageCollectedHeap;
  TYPE
    (* called with an object the collector found unreachable (RegisterFinalizer) *)
    Finalizer* = PROCEDURE(obj: SYSTEM.PTR);

  (* One full collection: roots, then the machine stack, then whatever
     they reach, then the sweep. Called by Allocate when it has run out
     of room, and directly by anything that wants one. *)
  PROCEDURE Collect*();

  (* dataSize bytes of zeroed memory whose tag word (at the returned
     address - one word) is tag - 0, or the address of a type descriptor.
     0 if the request is out of range or the heap ceiling stops it. *)
  PROCEDURE Allocate*(dataSize: SYSTEM.ADDRESS; tag: SYSTEM.ADDRESS): SYSTEM.ADDRESS;

  (* The base of the machine stack, as the program's `main` sees it. *)
  PROCEDURE SetStackBase*(base: SYSTEM.ADDRESS);

  (* The most bytes the heap may ask calloc for in total. A limit already
     below what is held is accepted; the heap just cannot grow. *)
  PROCEDURE SetHeapLimit*(bytes: SYSTEM.ADDRESS);

  (* The size the heap grows by (a bigger request gets a chunk of its
     own size). Takes effect for the next chunk. *)
  PROCEDURE SetChunkSize*(bytes: SYSTEM.ADDRESS);

  (* How many entries the mark stack holds - a tiny one exercises the
     overflow fallback. Only effective before the first collection. *)
  PROCEDURE SetMarkStackCapacity*(entries: SYSTEM.ADDRESS);

  (* The number of collections so far. *)
  PROCEDURE CollectionCount*(): LONGINT;

  (* Bytes obtained from calloc so far. *)
  PROCEDURE HeapBytes*(): SYSTEM.ADDRESS;

  (* Bytes in allocated blocks - headers and rounding included - the last
     collection found reachable. *)
  PROCEDURE LiveBytes*(): SYSTEM.ADDRESS;

  (* TRUE if address lies anywhere inside a block that is allocated now. *)
  PROCEDURE IsAllocated*(address: SYSTEM.ADDRESS): BOOLEAN;

  (* Finalizes every object pending or still registered, newest first,
     reachable or not, and those their finalizers register in turn: voc's
     Heap.FINALL. *)
  PROCEDURE FinalizeAll*();

  (* Has finalize called with obj when obj can no longer be reached, or
     when the program ends (FINALIZATION above). Nothing if obj is not an
     object on this heap, finalize is NIL, or calloc refuses the table
     room. *)
  PROCEDURE RegisterFinalizer*(obj: SYSTEM.PTR; finalize: Finalizer);
END GarbageCollectedHeap.
```

### In

```text
the Oakwood Guidelines' In module, formatted
input from the standard input stream, with voc's interface (src/
runtime/In.Mod): Open, Char, Int, LongInt, HugeInt, Real, LongReal,
Line, String, Name and the flag Done. Each reads what it can from the
stream, sets Done to say whether it found what it was asked for, and
leaves its argument alone (or, for some, zero) when it did not.

The stream is read a character at a time through C's getchar, which is
the same on Linux and the BSDs and buffered by libc, and one character
is read ahead of what a call has consumed - except at a line end, so
that a program prompting for a line does not wait for the next one
before it can use this one. The tokens are recognized by
FormattedInput, which InStr reads a string with too.

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):
- Open only starts over the reading state and Done; it does not seek
  standard input back to its start (D15).
- Real and LongReal read a whole line, take anything of the form
  [+-] digits [. digits] [E|D [+-] digits] as a number, and give the
  value the C library's strtof/strtod does (correctly rounded); a line
  not of that form leaves the number alone and sets Done FALSE (26).
- Name reads a word: what is left of the line after any blanks, up to
  the next blank (27).
- HugeInt (and so Int and LongInt) accepts decimal digits, or
  hexadecimal digits followed by H, either with a leading minus sign;
  a run of digits with letters in it and no H is Done = FALSE, value 0
  (25).
- Int and LongInt narrow the number the way voc's do, to the low bits,
  not by trapping.
```

```oberon
MODULE In;
  VAR
    (* whether the last operation succeeded; Open sets it TRUE *)
    Done-: BOOLEAN;

  (* Starts over: the next read begins wherever the stream is now. *)
  PROCEDURE Open*();

  (* The next character, line end (0AX) included. Done is FALSE, and ch 0X,
     at the end of the input. *)
  PROCEDURE Char*(VAR ch: CHAR);

  (* An integer: an optional minus sign, then decimal digits, or
     hexadecimal digits (0-9, A-F) and an H. *)
  PROCEDURE HugeInt*(VAR h: HUGEINT);
  PROCEDURE Int*(VAR i: INTEGER);
  PROCEDURE LongInt*(VAR i: LONGINT);

  (* The rest of the line - up to a line feed, and without the carriage
     return before it - cut short if line cannot hold it all (the rest is
     then left for the next read). Done is FALSE at the end of the input. *)
  PROCEDURE Line*(VAR line: ARRAY OF CHAR);

  (* A string in double quotes, on one line, without the quotes. *)
  PROCEDURE String*(VAR str: ARRAY OF CHAR);

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR name: ARRAY OF CHAR);
  PROCEDURE Real*(VAR x: REAL);
  PROCEDURE LongReal*(VAR x: LONGREAL);
END In.
```

### InStr

```text
In's procedures, except Open, reading from a string instead of standard
input (Phase 15's "Ongoing library enhancements" 2). Each takes In's
parameters followed by s and pos, starts reading at s[pos], and, when
it succeeds, moves pos to just after what it used up: the blanks it
skipped, then the number, word, quoted string (its closing quote
included), character or line (its line end included). One that fails
leaves pos alone, and its argument as In leaves its argument. Done, as
In's, says whether the last call found what it was asked for, so a run
of calls reads a string token by token as a run of In calls reads
standard input:

  pos := 0; InStr.Int(i, s, pos); InStr.Name(word, s, pos)

s ends at its first 0X, or at LEN(s) if it has none. A pos below 0 or
past that end reads nothing: Done is FALSE, and nothing traps.

The tokens are In's, recognized by the same code (FormattedInput), with
one difference: In.Real and In.LongReal read a whole line and take it
as one number, where these read the number at pos - after any blanks,
tabs and line ends, [+-] digits [. digits] [E|D [+-] digits] - and
stop after it, so that a string of numbers can be read one by one.

s is a read-only parameter, s-: it is not copied, so reading a long
string token by token costs no more than reading it once, and a string
constant may be passed. poc's own: voc has no InStr, nor read-only
parameters that take a constant.
```

```oberon
MODULE InStr;
  VAR
    (* whether the last operation succeeded *)
    Done-: BOOLEAN;

  (* The next character, line end (0AX) included; ch is 0X if there is
     none. *)
  PROCEDURE Char*(VAR ch: CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* An integer: an optional minus sign, then decimal digits, or
     hexadecimal digits (0-9, A-F) and an H. h is left alone if there is
     nothing left to read, and is 0 if what there is is not a number. *)
  PROCEDURE HugeInt*(VAR h: HUGEINT; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* HugeInt, narrowed to the low bits of an INTEGER, as In.Int: 0 if there
     is nothing left to read *)
  PROCEDURE Int*(VAR i: INTEGER; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* HugeInt, narrowed to the low bits of a LONGINT, as In.LongInt: 0 if
     there is nothing left to read *)
  PROCEDURE LongInt*(VAR i: LONGINT; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* The rest of the line - up to a line feed, and without the carriage
     return before it - cut short if line cannot hold it all (the rest is
     then left for the next read). Done is FALSE at the end of s. *)
  PROCEDURE Line*(VAR line: ARRAY OF CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* A string in double quotes, on one line, without the quotes; str is ""
     if there is none. *)
  PROCEDURE String*(VAR str: ARRAY OF CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR name: ARRAY OF CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* A real number, correctly rounded (the C library's strtof); x is left
     alone if there is none. *)
  PROCEDURE Real*(VAR x: REAL; s-: ARRAY OF CHAR; VAR pos: LONGINT);

  (* The same for a LONGREAL (strtod) *)
  PROCEDURE LongReal*(VAR x: LONGREAL; s-: ARRAY OF CHAR; VAR pos: LONGINT);
END InStr.
```

### Math

```text
the Oakwood REAL mathematics, with the
interface of voc's Math (which adapts the ISO RealMath of the OOC
library, adding log, ipower, sincos, arctan2, fcmp and the error
handler), so a program using it runs unchanged under either compiler.

Written afresh over the C library's double-precision functions (sqrt,
sin, exp, ... : the same names on Linux, NetBSD, OpenBSD and FreeBSD,
in libm, which the build now links), not derived from voc's, which is
the OOC library's polynomial approximations under the LGPL. A REAL
function widens its argument, calls the double function and rounds the
result once, so it is correct to within a rounding of the double
result (voc's own approximations are good to an ulp or two of a REAL).
The real-number properties (exponent, fraction, scale, ulp, succ, pred)
are exact.

Errors: a call that cannot give a real answer reports an error code
through ErrorHandler and returns a fixed value, as in voc. The default
handler stores the code in err (ClearError sets it back to NoError); a
program may install its own, taking the code as its argument, and a
handler that returns lets the function go on to its return value.
MathL reports through this same handler. What is an error, and what
comes back:

  ln(x), x <= 0        IllegalLog          -large
  log(x, base)         IllegalLogBase for base <= 0 or base = 1, or
                       IllegalLog for x <= 0                -large
  sqrt(x), x < 0       IllegalRoot         the root of -x
  exp(x)               Overflow            large
                       Underflow           0 (the result rounds to 0)
  power(b, e), b < 0   IllegalPower        the power of -b
  power(0, e), e <= 0  IllegalPower        large
  power(0, e), e > 0   0, no error
  power(b, e)          Overflow            large;  Underflow  0
  ipower(x, n)         Overflow            +-large (a result too large,
                                           or 0 to a negative power)
  arcsin/arccos(x), |x| > 1     IllegalInvTrig    large
  arctan2(0, 0)        IllegalTrig         0
  sinh, cosh           Overflow            +-large
  arccosh(x), x < 1    IllegalHypInvTrig   0
  arctanh(x), |x| >= 1 IllegalHypInvTrig   +-arctanh of the largest
                                           number below 1
  scale, succ, pred    Overflow            +-large

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):

- sin, cos and tan give an answer for every argument (48), and from
  libm, so with no error from constants that lose digits (03).
- exp reports Underflow only when the result is really 0 (55); arcsinh
  and arccosh have no clipping error (56).
- sincos gives the true cosine (38); succ and pred give the
  neighbouring numbers (39); sign(0) is 1, as in voc.
  fraction/exponent/scale/ulp are right for denormals too (42, 54):
  the exponent of a denormal is below expoMin, since it is the
  exponent the number would have with a longer exponent field.
- Lengths and codes are INTEGER, and round is LONGINT - the Oakwood
  interface's own types, which follow the size model, so they are not
  SYSTEM.INT16/INT32 (fixed-width; used only for the C `int` of ldexp).
  round rounds halves away from zero, as voc's (D10), and gives
  MAX(LONGINT)/MIN(LONGINT) for a number out of range (voc's wraps:
  D22).
```

```oberon
MODULE Math;
  CONST
    (* pi and e; the number of bits in the fraction (with its leading 1); the
       largest number and the smallest normal one; the largest and smallest
       exponent of a normal number *)
    pi* = 3.14159265358979323846;
    e* = 2.71828182845904523536;
    places* = 24;
    large* = MAX(REAL);
    small* = 1.17549435E-38;
    expoMax* = 127;
    expoMin* = -126;

    (* error codes *)
    NoError* = 0;
    IllegalRoot* = 1;
    IllegalLog* = 2;
    Overflow* = 3;
    IllegalPower* = 4;
    IllegalLogBase* = 5;
    IllegalTrig* = 6;
    IllegalInvTrig* = 7;
    HypInvTrigClipped* = 8;
    IllegalHypInvTrig* = 9;
    LossOfAccuracy* = 10;
    Underflow* = 11;
  VAR
    (* Called with the error code of a function that cannot give a real
       answer; at first a handler that stores the code in err. *)
    ErrorHandler*: PROCEDURE(errno: INTEGER);
    err-: INTEGER;

  (* err := NoError *)
  PROCEDURE ClearError*();

  (* Always FALSE: an error goes to the error handler, never to an exception
     (voc's interface keeps it from the ISO library). *)
  PROCEDURE IsRMathException*(): BOOLEAN;

  (* The exponent of x, the power of 2 with x = fraction(x) * 2^exponent(x):
     0 for 0, expoMax + 1 for an infinity or a not-a-number. *)
  PROCEDURE exponent*(x: REAL): INTEGER;

  (* x without its exponent, 1 <= |fraction(x)| < 2; 0, an infinity or a
     not-a-number comes back as it is. *)
  PROCEDURE fraction*(x: REAL): REAL;

  (* -1 if x is negative, else 1 (0 included). *)
  PROCEDURE sign*(x: REAL): REAL;

  (* x * 2^n, exactly where the result is representable. *)
  PROCEDURE scale*(x: REAL; n: INTEGER): REAL;

  (* The distance from |x| to the next larger number of x's exponent: one
     unit in the last place. *)
  PROCEDURE ulp*(x: REAL): REAL;

  (* The next number above x, pred the next below it. *)
  PROCEDURE succ*(x: REAL): REAL;
  PROCEDURE pred*(x: REAL): REAL;

  (* The elementary functions, each with the error in the module's table: the
     square root, e^x, the natural logarithm, the logarithm to the base, and
     base^exp. *)
  PROCEDURE sqrt*(x: REAL): REAL;
  PROCEDURE exp*(x: REAL): REAL;
  PROCEDURE ln*(x: REAL): REAL;
  PROCEDURE log*(x: REAL; base: REAL): REAL;
  PROCEDURE power*(base: REAL; exp: REAL): REAL;

  (* x to the whole power base (despite its name, voc's, base is the exponent). *)
  PROCEDURE ipower*(x: REAL; base: INTEGER): REAL;

  (* The trigonometric functions, in radians. *)
  PROCEDURE sin*(x: REAL): REAL;
  PROCEDURE cos*(x: REAL): REAL;
  PROCEDURE tan*(x: REAL): REAL;

  (* The sine and cosine of x at once. *)
  PROCEDURE sincos*(x: REAL; VAR Sin: REAL; VAR Cos: REAL);

  (* The inverse trigonometric functions, in radians: arcsin in -pi/2..pi/2,
     arccos in 0..pi, arctan in -pi/2..pi/2. *)
  PROCEDURE arcsin*(x: REAL): REAL;
  PROCEDURE arccos*(x: REAL): REAL;
  PROCEDURE arctan*(x: REAL): REAL;

  (* The angle of the point (xd, xn) from the positive x-axis, in -pi..pi: the
     arctangent of xn / xd in the right quadrant. *)
  PROCEDURE arctan2*(xn: REAL; xd: REAL): REAL;

  (* The hyperbolic functions and their inverses. *)
  PROCEDURE sinh*(x: REAL): REAL;
  PROCEDURE cosh*(x: REAL): REAL;
  PROCEDURE tanh*(x: REAL): REAL;
  PROCEDURE arcsinh*(x: REAL): REAL;
  PROCEDURE arccosh*(x: REAL): REAL;
  PROCEDURE arctanh*(x: REAL): REAL;

  (* x rounded to the nearest whole number, halves away from zero; a number
     that rounds beyond LONGINT gives its largest or smallest value. *)
  PROCEDURE round*(x: REAL): LONGINT;

  (* -1, 0 or 1 as x is less than, approximately equal to, or greater than
     y, "approximately" meaning within epsilon times the larger power of 2
     at or below the larger of |x| and |y| (the GNU Scientific Library's
     gsl_fcmp, as voc's). *)
  PROCEDURE fcmp*(x: REAL; y: REAL; epsilon: REAL): INTEGER;
END Math.
```

### MathL

```text
the Oakwood LONGREAL mathematics, the same
functions as Math (see there for the error codes, what comes back with
each, and how this differs from voc's) on LONGREAL, with the interface
of voc's MathL: everything Math has except the error handler, whose
ErrorHandler, err, ClearError and codes live in Math; a MathL function
reports through Math.ErrorHandler.

Each function is one call of the C library's double function (sqrt,
sin, exp, ... in libm) plus the error checks, so the result is what
libm gives: to within an ulp or better, and correctly rounded for
sqrt. Not derived from voc's MathL, which is the OOC library's
polynomial approximations under the LGPL.

Differences from Math beyond the width (the numbers are those of
vishap-bugs, ~/Repos/Oberon/vishap-bugs):
- `large` is MAX(LONGREAL) and `small` the smallest normal LONGREAL,
  2^-1022 (41).
- exp and power report Underflow when the result is 0, as Math does;
  voc's MathL reports none (D23).
```

```oberon
MODULE MathL;
  CONST
    (* pi and e; the number of bits in the fraction (with its leading 1); the
       largest number and the smallest normal one; the largest and smallest
       exponent of a normal number *)
    pi* = 3.14159265358979323846D0;
    e* = 2.71828182845904523536D0;
    places* = 53;
    large* = MAX(LONGREAL);
    small* = 2.2250738585072014D-308;
    expoMax* = 1023;
    expoMin* = -1022;

  (* Always FALSE: an error goes to the error handler, never to an exception
     (voc's interface keeps it from the ISO library). *)
  PROCEDURE IsRMathException*(): BOOLEAN;

  (* The exponent of x, the power of 2 with x = fraction(x) * 2^exponent(x):
     0 for 0, expoMax + 1 for an infinity or a not-a-number. *)
  PROCEDURE exponent*(x: LONGREAL): INTEGER;

  (* x without its exponent, 1 <= |fraction(x)| < 2; 0, an infinity or a
     not-a-number comes back as it is. *)
  PROCEDURE fraction*(x: LONGREAL): LONGREAL;

  (* -1 if x is negative, else 1 (0 included). *)
  PROCEDURE sign*(x: LONGREAL): LONGREAL;

  (* x * 2^n, exactly where the result is representable. *)
  PROCEDURE scale*(x: LONGREAL; n: INTEGER): LONGREAL;

  (* The distance from |x| to the next larger number of x's exponent: one
     unit in the last place. *)
  PROCEDURE ulp*(x: LONGREAL): LONGREAL;

  (* The next number above x, pred the next below it. *)
  PROCEDURE succ*(x: LONGREAL): LONGREAL;
  PROCEDURE pred*(x: LONGREAL): LONGREAL;

  (* The elementary functions, each with the error in the module's table: the
     square root, e^x, the natural logarithm, the logarithm to the base, and
     base^exp. *)
  PROCEDURE sqrt*(x: LONGREAL): LONGREAL;
  PROCEDURE exp*(x: LONGREAL): LONGREAL;
  PROCEDURE ln*(x: LONGREAL): LONGREAL;
  PROCEDURE log*(x: LONGREAL; base: LONGREAL): LONGREAL;
  PROCEDURE power*(base: LONGREAL; exp: LONGREAL): LONGREAL;

  (* x to the whole power base (despite its name, voc's, base is the exponent). *)
  PROCEDURE ipower*(x: LONGREAL; base: INTEGER): LONGREAL;

  (* The trigonometric functions, in radians. *)
  PROCEDURE sin*(x: LONGREAL): LONGREAL;
  PROCEDURE cos*(x: LONGREAL): LONGREAL;
  PROCEDURE tan*(x: LONGREAL): LONGREAL;

  (* The sine and cosine of x at once. *)
  PROCEDURE sincos*(x: LONGREAL; VAR Sin: LONGREAL; VAR Cos: LONGREAL);

  (* The inverse trigonometric functions, in radians: arcsin in -pi/2..pi/2,
     arccos in 0..pi, arctan in -pi/2..pi/2. *)
  PROCEDURE arcsin*(x: LONGREAL): LONGREAL;
  PROCEDURE arccos*(x: LONGREAL): LONGREAL;
  PROCEDURE arctan*(x: LONGREAL): LONGREAL;

  (* The angle of the point (xd, xn) from the positive x-axis, in -pi..pi: the
     arctangent of xn / xd in the right quadrant. *)
  PROCEDURE arctan2*(xn: LONGREAL; xd: LONGREAL): LONGREAL;

  (* The hyperbolic functions and their inverses. *)
  PROCEDURE sinh*(x: LONGREAL): LONGREAL;
  PROCEDURE cosh*(x: LONGREAL): LONGREAL;
  PROCEDURE tanh*(x: LONGREAL): LONGREAL;
  PROCEDURE arcsinh*(x: LONGREAL): LONGREAL;
  PROCEDURE arccosh*(x: LONGREAL): LONGREAL;
  PROCEDURE arctanh*(x: LONGREAL): LONGREAL;

  (* x rounded to the nearest whole number, halves away from zero; a number
     that rounds beyond LONGINT gives its largest or smallest value. *)
  PROCEDURE round*(x: LONGREAL): LONGINT;

  (* -1, 0 or 1 as x is less than, approximately equal to, or greater than
     y, "approximately" meaning within epsilon times the larger power of 2
     at or below the larger of |x| and |y| (the GNU Scientific Library's
     gsl_fcmp, as voc's). *)
  PROCEDURE fcmp*(x: LONGREAL; y: LONGREAL; epsilon: LONGREAL): INTEGER;
END MathL.
```

### ModuleTable (poc's own)

```text
the registry of every module's garbage-
collector root table - what the collector (GarbageCollectedHeap.Mod)
walks to find the pointers held in module-level variables.

A *root table* is a block of words the backend
(LLVMCodeGenerator.Mod) emits as a global for each module that has
pointer-typed module variables, and only in a program that contains
this module at all - so a program that never imports it pays for
nothing here:

  word 0        next   the next registered table (0 for the last;
                       written by Register, which links tables into
                       one list)
  word 1        count  N, the number of slots below
  words 2..N+1  slot   the *address of* one pointer-typed location -
                       a whole pointer variable, or a pointer inside
                       a record or array variable, flattened exactly
                       like the type descriptors' pointer-offset
                       tables (LLVMCodeGenerator.EmitPointerOffsets)

Every word is one target word wide. The compiled program's `_init`
for each such module calls Register with the table's address before
running the module's own body, so a pointer a module body stores
into a variable is already visible to a collection the body triggers.
Registration order is the reverse of module initialization order,
which no reader depends on.

MODULE DESCRIPTORS (PLAN.md Phase 12 step 5e). In a program that
contains the module Modules, the backend also emits for every module
a descriptor, @.module.<Module>, which its `_init` hands to
RegisterModule right after its imports' `_init` - so a module is
listed once its initialization has started, as in voc - laid out:

  word 0        next          the next registered descriptor (0 for
                              the last; written by RegisterModule)
  word 1        name          the address of the module's name, a
                              0X-terminated string
  word 2        importCount   I, the modules it imports
  word 3        commandCount  C, its commands: the exported
                              procedures with no parameters and no
                              result
  words 4..     I names of the modules imported, then C pairs: the
                command's name, the procedure's address

Modules reads them (ThisMod, ThisCommand, Free); nothing here does.

Everything is plain SYSTEM.ADDRESS arithmetic: this module has no
pointer variables of its own, hence no table of its own to register,
and can safely be registered *into* before its own body has run.
```

```oberon
MODULE ModuleTable;
  (* Lists a module's table of pointer locations, the collector's roots;
     called by the generated code, not by a program. *)
  PROCEDURE Register*(table: SYSTEM.ADDRESS);

  (* The first table of the registered list, or 0 when none is. *)
  PROCEDURE First*(): SYSTEM.ADDRESS;

  (* The table (or descriptor) listed after table, 0 after the last. *)
  PROCEDURE Next*(table: SYSTEM.ADDRESS): SYSTEM.ADDRESS;

  (* The number of pointer locations in table. *)
  PROCEDURE SlotCount*(table: SYSTEM.ADDRESS): SYSTEM.ADDRESS;

  (* The address of the index'th pointer location (0-based) of table. *)
  PROCEDURE Slot*(table: SYSTEM.ADDRESS; index: SYSTEM.ADDRESS): SYSTEM.ADDRESS;

  (* Lists a module descriptor (MODULE DESCRIPTORS above); called by the
     generated code, not by a program. *)
  PROCEDURE RegisterModule*(descriptor: SYSTEM.ADDRESS);

  (* The most recently registered module descriptor, 0 if none is; the
     next ones through Next, as tables. *)
  PROCEDURE FirstModule*(): SYSTEM.ADDRESS;

  (* The number of tables registered. *)
  PROCEDURE TableCount*(): LONGINT;
END ModuleTable.
```

### Modules

```text
voc's Modules module
(src/runtime/Modules.Mod) with its whole interface, poc's own code:
the command line (ArgCount, ArgVector, GetArg, GetIntArg, ArgPos),
the directory of the program's executable (BinaryDir), the list of
modules and their commands (ThisMod, ThisCommand, Free, res, resMsg,
imported, importing) and voc's run-time error stops (Halt,
AssertFail).

THE COMMAND LINE. A program that contains this module has a `main`
that takes argc and argv and passes both to Init before any module
body runs (LLVMCodeGenerator.GenerateProgram, the same pattern as the
stack base it hands the collector); a program that does not contain
it has an argument-less `main`. Init is exported because the
generated code calls it, not to be called by a program: a second call
would replace the arguments. Arguments are numbered as in C: 0 is the
program's own name as it was started, 1 the first argument, ArgCount
the number of them all.

MODULES AND COMMANDS. In a program that contains this module, every
module's `_init` lists a descriptor of it with ModuleTable as soon as
its imports are initialized (ModuleTable.Mod, "MODULE DESCRIPTORS"):
so, as in voc, a module is found once its initialization has started,
and only the modules linked into the program exist. A module's
commands are its exported procedures with no parameters and no
result, as voc's; ThisCommand gives one to call. The Module and Cmd
records are made from the descriptors when a program first looks
(ThisMod, ThisCommand, Free), newest module first, as voc's list.
m.refcnt is the number of listed modules that import m. Free, as
voc's, takes a module nothing imports off the list - so ThisMod no
longer finds it - but unloads nothing.

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):
- a module's or a command's name may have 255 characters (62);
- Module and Cmd are poc's own records, with the fields of voc's a
  program can use (next, name, refcnt, cmds; next, name, cmd), all
  read-only;
- Halt and AssertFail write their message to standard error, as
  poc's traps do, and the program's finalizers run after it
  (GarbageCollectedHeap, FINALIZATION) (D12, D13);
- GetArg with n outside 0..ArgCount-1 sets val to "", so a caller that
  ignores ArgCount never sees the previous argument again as this one
  (D11);
- MainStackFrame is argv's address, as poc's main has no variable
  holding it (D17).
```

```oberon
MODULE Modules;
  CONST
    (* the size of a module name's array *)
    ModNameLen* = 256;
  TYPE
    (* A module of the program, with its name, its number of importers
       (refcnt) and its exported parameterless procedures (cmds), each a
       command; both lists are read-only. *)
    ModuleName* = ARRAY 256 OF CHAR;
    Module* = POINTER TO ModuleDesc;
    Cmd* = POINTER TO CmdDesc;
    Command* = PROCEDURE;
    ModuleDesc* = RECORD next-: Module; name-: ModuleName; refcnt-: LONGINT; cmds-: Cmd END;
    CmdDesc* = RECORD next-: Cmd; name-: ARRAY 256 OF CHAR; cmd-: Command END;
  VAR
    (* 0 after a ThisMod, ThisCommand or Free that did what it was asked *)
    res*: INTEGER;

    (* what went wrong, when res # 0 *)
    resMsg*: ARRAY 256 OF CHAR;

    (* importing: the name the last ThisMod did not find; imported stays empty
       (voc's names a module whose import is missing, which cannot be here) *)
    imported*: ModuleName;
    importing*: ModuleName;

    (* near the bottom of the main stack: argv's address (above) *)
    MainStackFrame-: SYSTEM.ADDRESS;
    ArgCount-: INTEGER;

    (* argv: the address of an array of ArgCount strings' addresses *)
    ArgVector-: SYSTEM.ADDRESS;

    (* the directory of the program's executable, "" if not found *)
    BinaryDir-: ARRAY 1024 OF CHAR;

  (* Records the command line. Called once, by the program's `main`. *)
  PROCEDURE Init*(argc: SYSTEM.ADDRESS; argv: SYSTEM.ADDRESS);

  (* Argument n in val, cut short if val is too small for it. *)
  PROCEDURE GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR);

  (* Argument n as a number - an optional minus sign and decimal digits;
     val is left alone if it does not start with a digit (after the sign).
     Same as voc's. *)
  PROCEDURE GetIntArg*(n: INTEGER; VAR val: LONGINT);

  (* The number of the first argument (from 0) equal to s, ArgCount if
     none is. *)
  PROCEDURE ArgPos*(s: ARRAY OF CHAR): INTEGER;

  (* The module called name, or NIL (res 1, resMsg says so, importing is
     name) if there is none in the program or it has not been
     initialized yet. *)
  PROCEDURE ThisMod*(name: ARRAY OF CHAR): Module;

  (* The command called name of mod, or NIL (res 2, resMsg says so). *)
  PROCEDURE ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;

  (* Takes the module called name off the list if no listed module imports
     it (res 0), as voc's; nothing is unloaded. all is not done (res 1). *)
  PROCEDURE Free*(name: ARRAY OF CHAR; all: BOOLEAN);

  (* Stops the program with exit status code (its low 8 bits), saying so
     on standard error as voc's does, with what a negative code of voc's
     means. *)
  PROCEDURE Halt*(code: SYSTEM.INT32);

  (* Stops the program after a failed assertion with code, as voc's: exit
     status code if it is positive, else 255 (-1). *)
  PROCEDURE AssertFail*(code: SYSTEM.INT32);
END Modules.
```

### Oberon

```text
Phase 12 step 5h: voc's Oberon interface - the stub of the Oberon
system's module that programs written for it import: the log text,
the command's parameters, the clocks - written for poc. There is no
display, so no viewers, frames or selection.

Log is an empty text whose notifier echoes to standard output, through
Out, whatever is inserted into it (0DX as a line end). Par.text holds
the program's arguments, each followed by a blank, and Par.pos is 0,
as for a command called with its parameters after it.

Where it differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):
- An argument is copied whole (63).
- Only an insertion into Log is echoed (64).
```

```oberon
MODULE Oberon;
  TYPE
    (* a command's parameters: the text they are in, from pos on *)
    ParList* = POINTER TO ParRec;
    ParRec* = RECORD text*: Texts.Text; pos*: LONGINT END;
  VAR
    (* the log: what is inserted is written to standard output *)
    Log*: Texts.Text;

    (* the parameters of the command running: the program's arguments *)
    Par*: ParList;

    (* the character that starts an option, "-" *)
    OptionChar*: CHAR;

  (* The local time now: t = hour * 4096 + minute * 64 + second, d = (year
     MOD 100) * 512 + month * 32 + day (Platform's format). *)
  PROCEDURE GetClock*(VAR t: LONGINT; VAR d: LONGINT);

  (* The milliseconds since the program started. *)
  PROCEDURE Time*(): LONGINT;

  (* There is no selection: text NIL, and beg, end and time 0. *)
  PROCEDURE GetSelection*(VAR text: Texts.Text; VAR beg: LONGINT; VAR end: LONGINT; VAR time: LONGINT);
END Oberon.
```

### Out

```text
the Oakwood Guidelines' Out module, formatted
output to the standard output stream, with voc's interface (src/
runtime/Out.Mod): Open, Flush, Char, String, Int, Hex, Ln, Real,
LongReal, and voc's Ten and IsConsole. It is the module poc's own
Diagnostics.Mod prints through (Char, String, Int, Ln).

The formatting is FormattedOutput's, shared with Err (Phase 11 A26),
which writes the same to standard error. Like Console it is unbuffered:
every call has written its output when it returns, so Out, Err and
Console (and the trap messages) interleave in the order of the calls,
and nothing is lost when a program ends without a Ln. Flush and Open
therefore do nothing. voc buffers 128 characters and flushes at each
line end.

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):
- Real and LongReal are correctly rounded (Phase 11 step 2, inventory
  A3): the digits are the exact decimal expansion of the number,
  rounded to nearest, ties to even (RealDigits), and the exponent is
  that of the rounded digits (30, 32). The layout, the digit counts
  and the dropping of trailing zeros are voc's; a denormal prints its
  digits (31). The reading of text, In's, is the C library's, which is
  correct.
```

```oberon
MODULE Out;
  VAR
    (* whether the stream is a terminal *)
    IsConsole-: BOOLEAN;

  (* Initializes the output stream; there is nothing to do. *)
  PROCEDURE Open*();

  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*();
  PROCEDURE Char*(ch: CHAR);

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  PROCEDURE Ln*();

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x: HUGEINT; n: HUGEINT);

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x: HUGEINT; n: HUGEINT);

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER);

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
END Out.
```

### OutStr

```text
Out's output procedures - Char, String, Int, Hex, Ln, Real, LongReal -
appending to a string instead of writing to standard output (Phase 15's
"Ongoing library enhancements" 1). Each takes Out's parameters followed
by s, and adds its text at s's first 0X, so a run of calls builds a
line as a run of Out calls writes one; start with s := "".

The text is exactly Out's: FormattedText makes it for both, and the
field widths are padded with blanks the same way. Ln appends 0AX, the
line feed Out.Ln writes.

Text that does not fit is cut short, silently, and s always ends in a
0X: a call never writes beyond s. If s has no 0X, its last character
is replaced by one before anything is appended.

poc's own: voc has no OutStr, and String's read-only parameter, str-,
takes a string constant, which voc's would not.
```

```oberon
MODULE OutStr;
  (* ch *)
  PROCEDURE Char*(ch: CHAR; VAR s: ARRAY OF CHAR);

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. str may be s itself: its length is taken first. *)
  PROCEDURE String*(str-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);

  (* A line feed, 0AX *)
  PROCEDURE Ln*(VAR s: ARRAY OF CHAR);

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, whole if it takes more. No plus
     sign. *)
  PROCEDURE Int*(x: HUGEINT; n: HUGEINT; VAR s: ARRAY OF CHAR);

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x: HUGEINT; n: HUGEINT; VAR s: ARRAY OF CHAR);

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER; VAR s: ARRAY OF CHAR);

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER; VAR s: ARRAY OF CHAR);
END OutStr.
```

### Platform

```text
The operating-system services of voc's Platform module
(src/runtime/Platformunix.Mod), with its interface, so that a program
written against voc's compiles unchanged: files by handle, file
identities and times, the clock, the environment, the working
directory, signal handlers, memory from the system, running a shell
command and ending the process. PLAN.md Phase 10 step 2 brought what
poc's own driver needs (Chdir, CWD, GetEnv, PID, System, Unlink, Exit);
Phase 12 step 5a the rest.

Two parts. What is the same on Linux, NetBSD, OpenBSD and FreeBSD -
the C names chdir, exit, free, getcwd, getenv, getpid, isatty, malloc,
rename, system, unlink and their arguments - is declared here as
external ["C"] procedures. What is not - open's flags, errno and its
values, struct stat, the clock, signals - is in Platform.c beside this
file, compiled by clang for the target from the system's own headers
(decided with the user 2026-10-02), under names that start with
"Platform.-". Its header says why each is there.

An ErrorCode is 0 for success, otherwise the errno value of the call
that failed, as voc's: so its numbers differ between the systems, and
a program tests them with Absent, Inaccessible, TooManyFiles and the
others rather than comparing them with numbers.

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):

- PID is never negative: a pid that does not fit an INTEGER (16 bits
  under -O2) is reduced modulo 2^15, so the temporary file names built
  from it stay readable (61).
- Write writes everything, in as many write calls as it takes, and
  Delay sleeps the whole time even when a signal interrupts it (59,
  60).
- getEnv returns FALSE for a name with no 0X in it (below). It copies
  at most what val holds, as voc's does (D6).
- The C type `int` is written SYSTEM.INT32 in the external
  declarations here and in Console, Files, In, Out, Math and MathL:
  exactly four bytes under -O2 and -OC alike, as LONGINT (eight bytes
  under -OC) is not - which is wrong at once on a 32-bit target, whose
  calling convention puts every argument on the stack at its own width.
  (voc's LONGINT there does no harm: its declarations are C macros,
  D8.)

A string handed to a C function must end in 0X within its array; one
that does not is treated as naming nothing: the procedure fails with
ENOENT's error code where it returns one (GetEnv finds no variable,
System runs nothing and returns -1).
```

```oberon
MODULE Platform;
  CONST
    (* the handles of standard input, output and error *)
    StdIn* = 0;
    StdOut* = 1;
    StdErr* = 2;
  TYPE
    (* 0, or the errno value of a call that failed; an open file's
       descriptor *)
    ErrorCode* = INTEGER;
    FileHandle* = LONGINT;

    (* which file a file is, and when it was last modified *)
    FileIdentity* = RECORD  END;
  VAR
    (* whether the machine stores the least significant byte first; the
       process id; the working directory, as at the start and after Chdir; the
       whence values for Seek *)
    LittleEndian-: BOOLEAN;
    PID-: INTEGER;
    CWD-: ARRAY 256 OF CHAR;
    SeekSet-: INTEGER;
    SeekCur-: INTEGER;
    SeekEnd-: INTEGER;

    (* the line ending: LF on every system here *)
    NL-: ARRAY 3 OF CHAR;

  (* The error code of the last call that failed. *)
  PROCEDURE Error*(): INTEGER;

  (* Error tests: whether the error code e means too many open files, no
     such directory, a rename across file systems, no permission, no such
     file, a time-out, a refused or failed connection, or a call
     interrupted by a signal. NoSuchDirectory and Absent test the same
     codes. *)
  PROCEDURE TooManyFiles*(e: INTEGER): BOOLEAN;
  PROCEDURE NoSuchDirectory*(e: INTEGER): BOOLEAN;
  PROCEDURE DifferentFilesystems*(e: INTEGER): BOOLEAN;
  PROCEDURE Inaccessible*(e: INTEGER): BOOLEAN;
  PROCEDURE Absent*(e: INTEGER): BOOLEAN;
  PROCEDURE TimedOut*(e: INTEGER): BOOLEAN;
  PROCEDURE ConnectionFailed*(e: INTEGER): BOOLEAN;
  PROCEDURE Interrupted*(e: INTEGER): BOOLEAN;

  (* File and path name length limits: NAME_MAX and PATH_MAX *)
  PROCEDURE MaxNameLength*(): INTEGER;
  PROCEDURE MaxPathLength*(): INTEGER;

  (* Memory from the system, outside the collected heap: malloc and free *)
  PROCEDURE OSAllocate*(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE OSFree*(address: SYSTEM.ADDRESS);

  (* The value of the environment variable var in val, cut short if val is
     too small for it; FALSE, and val unchanged, when there is no such
     variable. *)
  PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;

  (* The value of the environment variable var in val, cut short if val is
     too small for it; "" when there is no such variable (or it is empty).
     Same as voc's. *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);

  (* Signals: handler is called with the signal's number when the process
     gets it (SIGINT, SIGQUIT, SIGILL). A handler stays in place until
     another replaces it. Its type, SignalHandler, is not exported (as in
     voc): PROCEDURE (signal: SYSTEM.INT32). *)
  PROCEDURE SetInterruptHandler*(handler: SignalHandler);
  PROCEDURE SetQuitHandler*(handler: SignalHandler);
  PROCEDURE SetBadInstructionHandler*(handler: SignalHandler);

  (* The local time now, in the Oberon system's format: d holds the year
     modulo 100 (bits 9 and up), the month 1..12 (bits 5-8) and the day
     (bits 0-4); t the hour (bits 12 and up), the minute (bits 6-11) and
     the second (bits 0-5). *)
  PROCEDURE GetClock*(VAR t: LONGINT; VAR d: LONGINT);

  (* The time now, in seconds and microseconds since 1970 (the seconds
     wrap in 2038 under -O2, where a LONGINT has 32 bits, as voc's). *)
  PROCEDURE GetTimeOfDay*(VAR sec: LONGINT; VAR usec: LONGINT);

  (* The milliseconds since the program started, modulo 7FFFFFFFH. *)
  PROCEDURE Time*(): LONGINT;

  (* Sleeps for ms milliseconds. *)
  PROCEDURE Delay*(ms: LONGINT);

  (* Runs cmd with the shell (/bin/sh -c), waits for it, and returns the
     wait status: 0 when the command succeeded, otherwise the exit code
     times 256 (plus the signal number if it was killed), or -1 if no shell
     could be run. Narrowed to an INTEGER as voc's is, so a large status
     may wrap; it does not wrap to 0. *)
  PROCEDURE System*(cmd: ARRAY OF CHAR): INTEGER;

  (* Opens the file n to read. *)
  PROCEDURE OldRO*(VAR n: ARRAY OF CHAR; VAR h: LONGINT): INTEGER;

  (* Opens the file n to read and write. *)
  PROCEDURE OldRW*(VAR n: ARRAY OF CHAR; VAR h: LONGINT): INTEGER;

  (* Creates the file n, or empties it if it is there, to read and write. *)
  PROCEDURE New*(VAR n: ARRAY OF CHAR; VAR h: LONGINT): INTEGER;

  (* Closes h. *)
  PROCEDURE Close*(h: LONGINT): INTEGER;

  (* Whether h is a terminal. *)
  PROCEDURE IsConsole*(h: LONGINT): BOOLEAN;

  (* Reads at most l bytes from h to the address p; n is how many it read,
     0 at the end of the file. *)
  PROCEDURE Read*(h: LONGINT; p: SYSTEM.ADDRESS; l: LONGINT; VAR n: LONGINT): INTEGER;

  (* Reads at most LEN(b) bytes from h into b; n is how many it read. *)
  PROCEDURE ReadBuf*(h: LONGINT; VAR b: ARRAY OF SYSTEM.BYTE; VAR n: LONGINT): INTEGER;

  (* Writes the l bytes at the address p to h. *)
  PROCEDURE Write*(h: LONGINT; p: SYSTEM.ADDRESS; l: LONGINT): INTEGER;

  (* Writes what the system holds of h to the disk. *)
  PROCEDURE Sync*(h: LONGINT): INTEGER;

  (* Moves h's position to offset from whence: SeekSet (the start),
     SeekCur (the position) or SeekEnd (the end). *)
  PROCEDURE Seek*(h: LONGINT; offset: LONGINT; whence: INTEGER): INTEGER;

  (* Cuts h, or extends it with zeros, to l bytes. *)
  PROCEDURE Truncate*(h: LONGINT; l: LONGINT): INTEGER;

  (* The length of h in l. *)
  PROCEDURE Size*(h: LONGINT; VAR l: LONGINT): INTEGER;

  (* The identity of the open file h, or of the file named n *)
  PROCEDURE Identify*(h: LONGINT; VAR identity: FileIdentity): INTEGER;
  PROCEDURE IdentifyByName*(n: ARRAY OF CHAR; VAR identity: FileIdentity): INTEGER;

  (* Whether i1 and i2 are the same file (device and inode); whether they
     were last modified at the same time (in seconds); target's time made
     source's (in the identity, not the file) *)
  PROCEDURE SameFile*(i1: FileIdentity; i2: FileIdentity): BOOLEAN;
  PROCEDURE SameFileTime*(i1: FileIdentity; i2: FileIdentity): BOOLEAN;
  PROCEDURE SetMTime*(VAR target: FileIdentity; source: FileIdentity);

  (* i's modification time, in local time in GetClock's format. *)
  PROCEDURE MTimeAsClock*(i: FileIdentity; VAR t: LONGINT; VAR d: LONGINT);

  (* Sets the file n's modification (and access) time to the local time
     given, month 1..12. *)
  PROCEDURE SetFileMTime*(VAR n: ARRAY OF CHAR; year: LONGINT; month: LONGINT; day: LONGINT; hour: LONGINT; minute: LONGINT; second: LONGINT): INTEGER;

  (* Deletes the file n. *)
  PROCEDURE Unlink*(VAR n: ARRAY OF CHAR): INTEGER;

  (* Renames the file o to n, replacing any file n. *)
  PROCEDURE Rename*(VAR o: ARRAY OF CHAR; VAR n: ARRAY OF CHAR): INTEGER;

  (* Makes the directory n the working directory, and updates CWD. *)
  PROCEDURE Chdir*(VAR n: ARRAY OF CHAR): INTEGER;

  (* Ends the process with status code, flushing C's buffered output first
     (voc's Platform.Exit, whose parameter is a LONGINT too). *)
  PROCEDURE Exit*(code: LONGINT);
END Platform.
```

### RealDigits (poc's own)

```text
Phase 11 step 2 (inventory A3): the exact decimal digits of a LONGREAL,
correctly rounded to any number of significant digits - what Out.Real
and Out.LongReal print from - or to a decimal place (Fixed, what
Texts.WriteRealFix prints from). Not part of the Oakwood library; an
internal module of the runtime, like GarbageCollectedHeap.

v = m * 2^e exactly, m an integer below 2^53 and e >= -1074 (both read
from v's bits), and m * 2^e is the integer m * 2^e when e >= 0 and the
integer m * 5^-e with the decimal point -e places from the end when e < 0
(10^-e = 2^-e * 5^-e), so the exact decimal expansion - up to 770 digits
for the smallest subnormal - is just the digits of a big integer, taken
four at a time by dividing by 10000. Rounding to n digits looks at the
exact digits after the n-th: up if the first is above 5 or is 5 with a
nonzero digit after it, to even on an exact tie.

No floating-point arithmetic is done at all, so the result cannot depend
on the host's precision, and every quantity is a HUGEINT, so nor can it
depend on the size model (LONGINT is 4 bytes under -O2 and 8 under -OC).
The big integers are 15-bit limbs; a product of two is below 2^30.

src/front/DecimalToDouble.Mod has the same algorithm in strict
Oberon-2 for the compiler's own use: poc's own source uses no extension
(HUGEINT, SYSTEM), and Stage 0 builds it with voc, which has no
counterpart of a new runtime module to link it against. The two are kept
in step by the fixtures of both (llvm-real-digits,
module-interface-extreme-reals).
```

```oberon
MODULE RealDigits;
  (* The digits of v > 0 (finite), rounded to precision significant digits
     (nearest, ties to even), in digits[0 .. precision - 1] followed by 0X:
     v is about d0.d1d2... * 10^exponent10. digits has room for precision + 1
     characters. *)
  PROCEDURE Digits*(v: LONGREAL; precision: INTEGER; VAR digits: ARRAY OF CHAR; VAR exponent10: INTEGER);

  (* v > 0 (finite) rounded to a multiple of 10^-decimals (nearest, ties to
     even), keeping at most maxSignificant significant digits (rounding
     there instead, if that comes first): the result is d0.d1... *
     10^exponent10, digits[0 .. count-1] (count <= maxSignificant; count = 0
     when it rounds to 0). The digits of any place outside 0 .. count-1 are
     0. digits has room for maxSignificant characters. *)
  PROCEDURE Fixed*(v: LONGREAL; decimals: INTEGER; maxSignificant: INTEGER; VAR digits: ARRAY OF CHAR; VAR count: INTEGER; VAR exponent10: INTEGER);
END RealDigits.
```

### Reals

```text
Phase 12 step 5f: voc's Reals interface - powers of ten, the binary
exponent of a REAL or LONGREAL, and the digits Texts writes a real
number from - written for poc.

Where it differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):
- Ten and TenL are correctly rounded, the C library's strtof/strtod of
  "1E<e>" (36), and a negative e gives 10^e (D20).
- Expo, SetExpo, ExpoL, SetExpoL and ConvertH/ConvertHL take the
  number's bits as an integer, so they do not depend on the byte
  order; the answers are voc's.
- ConvertL writes the low n digits of x's integer part exactly,
  however large x is (D18).

As voc's, ConvertH and ConvertHL write the bytes least significant
first, each as two hexadecimal digits, the high one first: the order
of the bytes in memory on a little-endian machine, on any machine
(D19).
```

```oberon
MODULE Reals;
  (* 10^e, correctly rounded; 0 or infinity beyond REAL's range *)
  PROCEDURE Ten*(e: INTEGER): REAL;

  (* 10^e, correctly rounded; 0 or infinity beyond LONGREAL's range *)
  PROCEDURE TenL*(e: INTEGER): LONGREAL;

  (* The biased exponent field of x: 0 for zero and the subnormals, 255
     for the infinities and NaNs *)
  PROCEDURE Expo*(x: REAL): INTEGER;

  (* x's biased exponent field := ex MOD 256 *)
  PROCEDURE SetExpo*(VAR x: REAL; ex: INTEGER);

  (* The biased exponent field of x: 0 for zero and the subnormals, 2047
     for the infinities and NaNs *)
  PROCEDURE ExpoL*(x: LONGREAL): INTEGER;

  (* x's biased exponent field := ex MOD 2048 *)
  PROCEDURE SetExpoL*(VAR x: LONGREAL; ex: INTEGER);

  (* d[0 .. n-1] := the low n decimal digits of the integer part of |x|,
     least significant first, "0"s past its first digit. Texts calls it with
     x scaled to the n digits it wants. x = m * 2^e exactly (m < 2^53, from
     x's bits), so for e < 0 the integer part is m DIV 2^-e, and for e >= 0
     its low n digits are m's, doubled e times, each time keeping n digits.
     An infinity or NaN gives the digits of its bits read as a number. *)
  PROCEDURE ConvertL*(x: LONGREAL; n: INTEGER; VAR d: ARRAY OF CHAR);

  (* ConvertL of x *)
  PROCEDURE Convert*(x: REAL; n: INTEGER; VAR d: ARRAY OF CHAR);

  (* d[0 .. 7] := y's 4 bytes in hexadecimal (BytesToHex) *)
  PROCEDURE ConvertH*(y: REAL; VAR d: ARRAY OF CHAR);

  (* d[0 .. 15] := x's 8 bytes in hexadecimal (BytesToHex) *)
  PROCEDURE ConvertHL*(x: LONGREAL; VAR d: ARRAY OF CHAR);
END Reals.
```

### Strings

```text
operations on strings - character arrays that
end in 0X - with the interface of voc's Strings (which is the Oakwood
one, plus voc's Match, StrToReal and StrToLongReal), so a program using
it runs unchanged under either compiler. All positions start at 0. Pure
Oberon-2 apart from the two conversions, which hand a numeral to libc.

Length(s)              the characters before the first 0X (all of s if it
                       has none), at most MAX(INTEGER)
Insert(src, pos, dst)  src put into dst before position pos; a pos below
                       0 counts as 0, one above Length(dst) as
                       Length(dst) (append)
Append(s, dst)         Insert(s, Length(dst), dst)
Delete(s, pos, n)      n characters removed from s from pos on; fewer if
                       s ends first; nothing if pos is not inside s
Replace(src, pos, dst) Delete(dst, pos, Length(src)) then
                       Insert(src, pos, dst)
Extract(src, pos, n, dst)  dst := the n characters of src from pos on
                       (fewer if src ends first)
Pos(pat, s, pos)       where pat first occurs in s at or after pos, or -1
Cap(s)                 lower case letters made upper case
Match(s, pattern)      whether s is what pattern describes: any character
                       stands for itself and "*" for any run of
                       characters, an empty one included
StrToReal, StrToLongReal  the number a numeral at the start of s denotes

Every procedure that writes a string leaves it ended by a 0X: a result
too long for dst is cut short to fit (dst is never left unterminated,
as voc's Append and Extract can leave it).

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):

- Insert with a position past the end of dst appends (18), and Replace
  deletes Length(src) characters (19).
- Extract, Insert and Append never write beyond dst (20, 21), and Cap
  never reads beyond a string that has no 0X (57).
- Pos with a negative pos starts at 0 (22). An empty pattern is found
  at 0 whatever pos is, as in voc.
- StrToReal/StrToLongReal read blanks, an optional sign, digits, an
  optional fraction and an optional exponent (E or D, also in lower
  case, its sign + or -), and give the value libc's strtof/strtod does
  for it, correctly rounded (28, 29). Anything after the numeral is
  ignored, and a string with no number at the start gives 0, as in
  voc. A numeral of more than maxNumeral characters leaves the result
  variable alone.
- Lengths and positions are INTEGER, as in voc; under the -O2 size
  model that is 16 bits, so Length stops counting at 32767 (D21). All
  the work is done in LONGINT and never wraps.
```

```oberon
MODULE Strings;
  PROCEDURE Length*(s: ARRAY OF CHAR): INTEGER;
  PROCEDURE Insert*(source: ARRAY OF CHAR; pos: INTEGER; VAR dest: ARRAY OF CHAR);
  PROCEDURE Append*(extra: ARRAY OF CHAR; VAR dest: ARRAY OF CHAR);
  PROCEDURE Delete*(VAR s: ARRAY OF CHAR; pos: INTEGER; n: INTEGER);
  PROCEDURE Replace*(source: ARRAY OF CHAR; pos: INTEGER; VAR dest: ARRAY OF CHAR);
  PROCEDURE Extract*(source: ARRAY OF CHAR; pos: INTEGER; n: INTEGER; VAR dest: ARRAY OF CHAR);
  PROCEDURE Pos*(pattern: ARRAY OF CHAR; s: ARRAY OF CHAR; pos: INTEGER): INTEGER;
  PROCEDURE Cap*(VAR s: ARRAY OF CHAR);

  (* Whether string matches pattern, "*" standing for any run of
     characters. The usual greedy scan with one place to go back to: the
     last "*" seen, and how much of the string it has swallowed so far. *)
  PROCEDURE Match*(string: ARRAY OF CHAR; pattern: ARRAY OF CHAR): BOOLEAN;
  PROCEDURE StrToReal*(s: ARRAY OF CHAR; VAR r: REAL);
  PROCEDURE StrToLongReal*(s: ARRAY OF CHAR; VAR r: LONGREAL);
END Strings.
```

### Texts

```text
Phase 12 step 5g: voc's Texts interface - Oberon texts kept in files,
with readers, scanners, writers and elements, and no display - written
for poc.

TEXTS AS PIECES. A text is a ring of runs behind a sentinel: each run
is a piece (len bytes of a file, from org on) or an element (one
character, ElemChar, standing for an object with a handler). Nothing
is ever copied: a writer appends what it is given to a temporary file
of its own and keeps pieces of it in its buffer; inserting a buffer
into a text splices those pieces into the text's ring, deleting moves
them out again, and Store finally copies what the pieces cover into
the file being written. Every run has looks: a font (only its name is
kept), a colour and a vertical offset. Two neighbouring pieces with the
same looks covering adjacent bytes of the same file are merged.

THE FILE FORMAT is Oberon V4's, as voc's: Open reads a text file
(0F0X, 01X: what Close writes), the text in an Oberon System 3
document (0F7X, 07X), or any other file as plain text; Store and Load
read and write the text alone, and Load also takes the V4 tag
(0F001H) in front. A text file is a header - its length, the runs
(font number, the font's name the first time it is used, colour,
offset, length or an element's description), 0X and the text's length
- then the characters. An element is stored by its handler (FileMsg)
under the module and procedure its IdentifyMsg answer names, and
loaded by calling that procedure as a command (Modules.ThisCommand),
which leaves the new element in new; one whose command cannot be found
is kept as an alien element that stores its bytes back unchanged.

PLAIN TEXT. A file read as plain text keeps its line ends: Read gives
CR for LF, and for CR LF one CR (its position counts both), and Store
writes CR for each line end, so a text Close writes from it has the
Oberon line ends.

Where this differs from voc's (the numbers are those of vishap-bugs,
~/Repos/Oberon/vishap-bugs):
- Real numbers are written with correctly rounded digits (RealDigits),
  a subnormal one with its digits (44), an infinity as "Infinity"
  (43); WriteRealFix keeps the k decimals asked for, to at most 9
  significant digits, the rest "0"s (45).
- Scan reads a real number correctly rounded (strtof/strtod; 66); one
  past REAL's or LONGREAL's range is an infinity (46). A number of more
  than 255 characters is Inval (65).
- CR LF in a plain text file is one line end when stored, as when
  read (50).
- A text loaded from a file has its fonts (49).
- An element whose handler does not copy it is left out of a copy
  (51). Positions and lengths are clamped to the text, as in voc (D7).
- WriteInt pads -9223372036854775808 like any other number (53), and
  file names may be as long as Files allows (52).
```

```oberon
MODULE Texts;
  CONST
    (* the character an element reads as *)
    ElemChar* = 1CX;

    (* FileMsg.id *)
    load* = 0;
    store* = 1;

    (* Notifier op *)
    replace* = 0;
    insert* = 1;
    delete* = 2;
    unmark* = 3;

    (* Scanner.class *)
    Inval* = 0;
    Name* = 1;
    String* = 2;
    Int* = 3;
    Real* = 4;
    LongReal* = 5;
    Char* = 6;
  TYPE
    (* an element, a buffer of runs not yet in a text, a text *)
    Elem* = POINTER TO ElemDesc;
    Buffer* = POINTER TO BufDesc;
    Text* = POINTER TO TextDesc;

    (* the base of the messages an element's handler is sent *)
    ElemMsg* = RECORD  END;
    Handler* = PROCEDURE(e: Elem; VAR msg: ElemMsg);

    (* W and H are the element's size, for a display (unused here) *)
    ElemDesc* = RECORD (RunDesc) W*: LONGINT; H*: LONGINT; handle*: Handler END;

    (* load or store (id) the element at text position pos, with r *)
    FileMsg* = RECORD (ElemMsg) id*: INTEGER; pos*: LONGINT; r*: Files.Rider END;

    (* asks for a copy of the element, in e (NIL: none) *)
    CopyMsg* = RECORD (ElemMsg) e*: Elem END;

    (* asks for the module and procedure (a command) that load the element *)
    IdentifyMsg* = RECORD (ElemMsg) mod*: ARRAY 32 OF CHAR; proc*: ARRAY 32 OF CHAR END;
    BufDesc* = RECORD len*: LONGINT END;

    (* called after every change to a text that has one, with what changed
       (replace, insert, delete) and the positions beg..end it covered *)
    Notifier* = PROCEDURE(T: Text; op: INTEGER; beg: LONGINT; end: LONGINT);
    TextDesc* = RECORD len*: LONGINT; notify*: Notifier END;

    (* reads a text from a position: eot at its end; each character's looks in
       fnt, col and voff, and elem the element when the character is one *)
    Reader* = RECORD eot*: BOOLEAN; fnt*: Font; col*: SYSTEM.INT8; voff*: SYSTEM.INT8; elem*: Elem END;

    (* reads a text by tokens (Scan): the token's class (Inval, Name, ...) and
       its value in s and len (a name or string), i (Int), x (Real), y
       (LongReal) or c (Char); nextCh the character after it; line the line
       ends passed *)
    Scanner* = RECORD (Reader) nextCh*: CHAR; line*: INTEGER; class*: INTEGER; i*: LONGINT; x*: REAL; y*: LONGREAL; c*: CHAR; len*: SHORTINT; s*: ARRAY 64 OF CHAR END;

    (* writes into its buffer buf, with the looks fnt, col and voff, until the
       buffer is inserted into a text *)
    Writer* = RECORD buf*: Buffer; fnt*: Font; col*: SYSTEM.INT8; voff*: SYSTEM.INT8 END;
  VAR
    (* set by the command that loads an element *)
    new*: Elem;

  (* Copies the fields of SE that every element has into DE: for a handler
     making a copy. *)
  PROCEDURE CopyElem*(SE: Elem; DE: Elem);

  (* The text E is in, NIL if none; ElemPos its position there. *)
  PROCEDURE ElemBase*(E: Elem): Text;
  PROCEDURE ElemPos*(E: Elem): LONGINT;

  (* Makes B an empty buffer. *)
  PROCEDURE OpenBuf*(B: Buffer);

  (* Appends a copy of what SB holds to DB. *)
  PROCEDURE Copy*(SB: Buffer; DB: Buffer);

  (* What the last Delete took out, NIL if it has been recalled. *)
  PROCEDURE Recall*(VAR B: Buffer);

  (* Appends a copy of T's beg..end to B. *)
  PROCEDURE Save*(T: Text; beg: LONGINT; end: LONGINT; B: Buffer);

  (* Moves what B holds into T at pos, leaving B empty; Append inserts at
     the end. *)
  PROCEDURE Insert*(T: Text; pos: LONGINT; B: Buffer);
  PROCEDURE Append*(T: Text; B: Buffer);

  (* Takes beg..end out of T (Recall gives it back). *)
  PROCEDURE Delete*(T: Text; beg: LONGINT; end: LONGINT);

  (* Sets the looks of T's beg..end that sel names: 0 the font (unless fnt
     is NIL), 1 the colour, 2 the vertical offset. *)
  PROCEDURE ChangeLooks*(T: Text; beg: LONGINT; end: LONGINT; sel: SET; fnt: Font; col: SYSTEM.INT8; voff: SYSTEM.INT8);

  (* Sets R to read T from pos. *)
  PROCEDURE OpenReader*(VAR R: Reader; T: Text; pos: LONGINT);

  (* The next character: ElemChar for an element, 0X with eot at the end. *)
  PROCEDURE Read*(VAR R: Reader; VAR ch: CHAR);

  (* Moves R on to just past the next element, in elem (NIL and eot if there
     is none); ReadPrevElem moves back to the one before R. *)
  PROCEDURE ReadElem*(VAR R: Reader);
  PROCEDURE ReadPrevElem*(VAR R: Reader);

  (* The position R reads next. *)
  PROCEDURE Pos*(VAR R: Reader): LONGINT;

  (* Sets S to scan T from pos. *)
  PROCEDURE OpenScanner*(VAR S: Scanner; T: Text; pos: LONGINT);

  (* Reads the next token: a name (a letter, "/" or "." first, then
     letters, digits, "_", "." and "/", at most 63), a string in quotes
     (at most 63 characters, ending at the quote or a control character;
     len counts one more, as voc's), an integer (decimal, or hexadecimal
     followed by H, its last 8 digits as a 32-bit pattern), a real number
     (digits "." digits, then E or, for a LONGREAL, D, and a scale factor),
     or any other character. A number with hexadecimal letters and no H is
     Inval. Blanks, tabs and line ends before it are skipped, and the line
     ends counted in line. *)
  PROCEDURE Scan*(VAR S: Scanner);

  (* Makes W a writer with an empty buffer and the default looks. *)
  PROCEDURE OpenWriter*(VAR W: Writer);

  (* Sets the looks of what W writes next. *)
  PROCEDURE SetFont*(VAR W: Writer; fnt: Font);
  PROCEDURE SetColor*(VAR W: Writer; col: SYSTEM.INT8);
  PROCEDURE SetOffset*(VAR W: Writer; voff: SYSTEM.INT8);

  (* Appends ch to W's buffer, WriteElem e (an element in no text), WriteLn
     a line end, CR. *)
  PROCEDURE Write*(VAR W: Writer; ch: CHAR);
  PROCEDURE WriteElem*(VAR W: Writer; e: Elem);
  PROCEDURE WriteLn*(VAR W: Writer);

  (* s up to its first control character (0X included) *)
  PROCEDURE WriteString*(VAR W: Writer; s: ARRAY OF CHAR);

  (* x right-aligned in n characters *)
  PROCEDURE WriteInt*(VAR W: Writer; x: SYSTEM.INT64; n: SYSTEM.INT64);

  (* a blank, then x's low 32 bits as 8 hexadecimal digits *)
  PROCEDURE WriteHex*(VAR W: Writer; x: LONGINT);

  (* x in n characters: blanks, sign, d.ddd, "E", sign, 2 digits, with 2
     to 8 digits; 0 as "  0" and blanks *)
  PROCEDURE WriteReal*(VAR W: Writer; x: REAL; n: INTEGER);

  (* x in n characters with k decimals: blanks, sign, digits, ".", k
     digits, at most 9 of them significant; 0 as "0" and blanks *)
  PROCEDURE WriteRealFix*(VAR W: Writer; x: REAL; n: INTEGER; k: INTEGER);

  (* x's 4 bytes in hexadecimal, least significant first (Reals.ConvertH) *)
  PROCEDURE WriteRealHex*(VAR W: Writer; x: REAL);

  (* x in n characters: blanks, sign, d.ddd, "D", sign, 3 digits, with 2
     to 16 digits; 0 as "  0" and blanks *)
  PROCEDURE WriteLongReal*(VAR W: Writer; x: LONGREAL; n: INTEGER);

  (* x's 8 bytes in hexadecimal, least significant first (Reals.ConvertHL) *)
  PROCEDURE WriteLongRealHex*(VAR W: Writer; x: LONGREAL);

  (* " dd.mm.yy hh:mm:ss" from the clock's t and d (Oberon's packing) *)
  PROCEDURE WriteDate*(VAR W: Writer; t: LONGINT; d: LONGINT);

  (* Reads a text, its header and characters (after an optional V4 tag),
     from r into T. *)
  PROCEDURE Load*(VAR r: Files.Rider; T: Text);

  (* T as the file name holds it (see THE FILE FORMAT above); empty if
     there is no such file. *)
  PROCEDURE Open*(T: Text; name: ARRAY OF CHAR);

  (* Writes T, header and characters, to r. *)
  PROCEDURE Store*(VAR r: Files.Rider; T: Text);

  (* Writes T to the file name, keeping what was there as name.Bak. *)
  PROCEDURE Close*(T: Text; name: ARRAY OF CHAR);
END Texts.
```

### VT100

```text
terminal control with ANSI (ECMA-48) escape
sequences, as a VT100 and every terminal emulator since read them,
with the interface of voc's VT100 module (src/runtime/VT100.Mod): the
same constants, the variable CSI and the same procedures. Written for
poc, not derived from voc's. Each procedure writes its sequence to
standard output through Out, in one piece.

The constants ending in "m" are Select Graphic Rendition parameters,
for SetAttr: SetAttr(VT100.Red) turns the text red, and
SetAttr(VT100.ResetAll) back to normal. The procedures with a count n
(CUU, ED, SGR, ...) write CSI, n in decimal and their letter.

Where this differs from voc's (decided with the user 2026-10-02; the
numbers are those of vishap-bugs, ~/Repos/Oberon/vishap-bugs):
- a number is written whole (33);
- DSR(n) sends n (34);
- SetAttr writes all of attr (35).
```

```oberon
MODULE VT100;
  CONST
    (* ESC, SYN and the "[" that follows ESC in a control sequence *)
    Escape* = 1BX;
    SynchronousIdle* = 16X;
    LeftCrotchet* = "[";

    (* text attributes *)
    Bold* = "1m";
    Dim* = "2m";
    Underlined* = "4m";

    (* a console and xterm blink; many emulators do not *)
    Blink* = "5m";

    (* foreground and background colours swapped *)
    Reverse* = "7m";

    (* not shown: for a password *)
    Hidden* = "8m";

    (* attributes turned off *)
    ResetAll* = "0m";
    ResetBold* = "21m";
    ResetDim* = "22m";
    ResetUnderlined* = "24m";
    ResetBlink* = "25m";
    ResetReverse* = "27m";
    ResetHidden* = "28m";

    (* text colours *)
    Black* = "30m";
    Red* = "31m";
    Green* = "32m";
    Yellow* = "33m";
    Blue* = "34m";
    Magenta* = "35m";
    Cyan* = "36m";
    LightGray* = "37m";
    Default* = "39m";
    DarkGray* = "90m";
    LightRed* = "91m";
    LightGreen* = "92m";
    LightYellow* = "93m";
    LightBlue* = "94m";
    LightMagenta* = "95m";
    LightCyan* = "96m";
    White* = "97m";

    (* background colours *)
    BBlack* = "40m";
    BRed* = "41m";
    BGreen* = "42m";
    BYellow* = "43m";
    BBlue* = "44m";
    BMagenta* = "45m";
    BCyan* = "46m";
    BLightGray* = "47m";
    BDefault* = "49m";
    BDarkGray* = "100m";
    BLightRed* = "101m";
    BLightGreen* = "102m";
    BLightYellow* = "103m";
    BLightBlue* = "104m";
    BLightMagenta* = "105m";
    BLightCyan* = "106m";
    BWhite* = "107m";
  VAR
    (* the Control Sequence Introducer every sequence but Reset's starts
       with: ESC [ *)
    CSI*: ARRAY 5 OF CHAR;

  (* int in decimal, with a minus sign if it is negative, in str; cut short
     if str is too small for it. *)
  PROCEDURE IntToStr*(int: LONGINT; VAR str: ARRAY OF CHAR);

  (* Resets the terminal to its initial state (ESC c), then ends the line. *)
  PROCEDURE Reset*();

  (* Cursor Up *)
  PROCEDURE CUU*(n: INTEGER);

  (* Cursor Down *)
  PROCEDURE CUD*(n: INTEGER);

  (* Cursor Forward *)
  PROCEDURE CUF*(n: INTEGER);

  (* Cursor Back *)
  PROCEDURE CUB*(n: INTEGER);

  (* Cursor Next Line: to the start of the line n lines down *)
  PROCEDURE CNL*(n: INTEGER);

  (* Cursor Previous Line: to the start of the line n lines up *)
  PROCEDURE CPL*(n: INTEGER);

  (* Cursor Horizontal Absolute: to column n *)
  PROCEDURE CHA*(n: INTEGER);

  (* Cursor Position: to row n, column m, both counted from 1 *)
  PROCEDURE CUP*(n: INTEGER; m: INTEGER);

  (* Erase in Display: from the cursor to the end of the screen (n = 0), to
     its start (1), or all of it (2) *)
  PROCEDURE ED*(n: INTEGER);

  (* Erase in Line: from the cursor to the end of the line (n = 0), to its
     start (1), or all of it (2); the cursor stays where it is *)
  PROCEDURE EL*(n: INTEGER);

  (* Scroll Up: the page moves up n lines, new ones appear at the bottom *)
  PROCEDURE SU*(n: INTEGER);

  (* Scroll Down: the page moves down n lines, new ones appear at the top *)
  PROCEDURE SD*(n: INTEGER);

  (* Horizontal and Vertical Position: as CUP *)
  PROCEDURE HVP*(n: INTEGER; m: INTEGER);

  (* Select Graphic Rendition: the attribute or colour n (0 resets them) *)
  PROCEDURE SGR*(n: INTEGER);

  (* Select Graphic Rendition: the attributes or colours n and m *)
  PROCEDURE SGR2*(n: INTEGER; m: INTEGER);

  (* Device Status Report: DSR(6) asks the terminal for the cursor's
     position, which it sends back as input, ESC [ row ; column R *)
  PROCEDURE DSR*(n: INTEGER);

  (* Save Cursor Position *)
  PROCEDURE SCP*();

  (* Restore Cursor Position *)
  PROCEDURE RCP*();

  (* Hides the cursor. *)
  PROCEDURE DECTCEMl*();

  (* Shows the cursor. *)
  PROCEDURE DECTCEMh*();

  (* CSI attr: SetAttr(Bold), SetAttr("1;31m") *)
  PROCEDURE SetAttr*(attr: ARRAY OF CHAR);
END VT100.
```

<!-- rtl-reference end -->
