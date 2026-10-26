# `DESC`: an array passed by a `CLASS_A` descriptor

A proposal (2026-10-26), **not approved and not built**. It came out of
the POISE SPL binding (`~/Repos/Oberon/oPOISE-DMS`, Phase 0),
whose BASIC routines take arrays by a `CLASS_A` descriptor that the
caller now has to build by hand. It extends the table in
`language-extensions.md`, "How a `["VMS"]` procedure takes its
arguments", whose last item names "descriptors of other classes" as not
yet done.

## The problem

A `["VMS"]` declaration says how each argument is passed, and poc builds
what is needed at the call (`vms-sdl-interfaces.md`, part 1). An open
`ARRAY OF CHAR` gets a `CLASS_S` descriptor that way. Any other array
goes by reference, element 0's address, with no lengths; a routine that
wants a `CLASS_A` descriptor is declared with a `SYSTEM.ADDRESS` instead,
and every caller builds the descriptor in a record and passes its
address:

    VAR choices: ARRAY 4 OF ARRAY 10 OF CHAR;
        descriptor: VmsArguments.ArrayDescriptor;
    ...
    VmsArguments.DescribeArray(descriptor, choices);
    status := SMG_ROUTINES.SMG$CREATE_MENU(menu, SYSTEM.ADR(descriptor), ...);

That has three faults. The declaration says nothing of what the routine
takes: any address will do. Each caller repeats the building, and must
get the data type, sizes and flags right. And `ArrayDescriptor` is the
16-byte prototype block alone, which `SMG$` accepts but VAX BASIC does
not: BASIC reads the coefficient and bounds block too (below).

Who needs it, so far:
- **`SMG$CREATE_MENU`**, `SMG$` choices: a one-dimensional array of
  fixed-length strings (`vax-vms-guide.md`, "Keys and menus").
- **Routines written in VAX BASIC**, which take every array argument
  (`X%()`, `X()`) by a `CLASS_A` descriptor. In the POISE SPL that is
  13 routines; two take integer arrays (`UTL_STRIP_QUALS`'s `CCBITS%()`,
  `FIO_FIND_DUPKEY`'s `RECS%()`), eleven string arrays.
- FORTRAN's assumed-shape and other descriptor-taking routines, if a
  binding to one is ever wanted.

## What VAX BASIC passes and reads (found 2026-10-26)

Dumped from a BASIC caller on the guest (POISE binding,
`experiments/exp03`), for `DIM CC%(5%)`, a LONG array with subscripts 0
to 5:

| Longword | Value | Field |
|---|---|---|
| 0 | `04080004` | length 4 (an element, in bytes), dtype 8 (`L`), class 4 (`A`) |
| 1 | the array | `DSC$A_POINTER`, the first element |
| 2 | `01D00000` | scale 0, digits 0, aflags `0D0X` (`FL_REDIM`, `FL_COEFF`, `FL_BOUNDS`), dimct 1 |
| 3 | 24 | `DSC$L_ARSIZE`, the whole array, in bytes |
| 4 | the array | `DSC$A_A0`, element (0)'s address |
| 5 | 6 | `DSC$L_M1`, the first dimension's multiplier: its element count |
| 6 | 0 | `DSC$L_L1`, the lower bound |
| 7 | 5 | `DSC$L_U1`, the upper bound |

An Oberon caller that built exactly this, in a record, passed by
`SYSTEM.ADDRESS`, got the same results from `UTL_STRIP_QUALS` as the
BASIC caller did, under `-O2` and `-OC` (`experiments/exp04`, `exp05`).
A string array (`ARGS$()`) is the same with length 8 and dtype 24
(`DSC`): its elements are themselves descriptors, `CLASS_D` strings the
callee allocates. That case is out of this proposal's reach (proposal 6).

## Proposals

1. **`DESC` before an array formal type, in a `["VMS"]` declaration
   only**, marks the parameter as passed by a `CLASS_A` descriptor that
   the caller builds:

       PROCEDURE ["VMS", "UTL_STRIP_QUALS"] StripQuals(result: SYSTEM.ADDRESS;
         strng-, legals-: ARRAY OF CHAR; VAR ccbits: DESC ARRAY OF SYSTEM.INT32;
         VAR found: SYSTEM.INT32; args: SYSTEM.ADDRESS);
       PROCEDURE ["VMS", "SMG$CREATE_MENU"] CREATE_MENU*(
         display-: SYSTEM.CARD32; choices-: DESC ARRAY OF ARRAY OF CHAR; ...

   - **The syntax.** `FormalType = [DESC] {ARRAY OF} Qualident.` `DESC`
     is not a reserved word: it is recognized only there, where an
     identifier followed by `ARRAY` could mean nothing else, so a module
     with a `DESC` of its own still compiles. The word is short and
     VMS's own (`DSC$`, `%DESCR`, BASIC's `BY DESC`).
   - **On the parameter, not the type.** The actual is an ordinary
     Oberon array; the descriptor is built in the caller's frame at each
     call and kept until `CALLG` returns, as a `CLASS_S` one is now. No
     variable has a descriptor type, nothing about assignment or type
     compatibility changes, and a program that never declares a
     `["VMS"]` routine sees nothing new.
   - **Only open arrays.** The bounds come from `LEN`, so one declaration
     takes any length, as a `CLASS_S` string does. A named fixed array
     type after `DESC` is refused: write it open.
   - **`VAR` or `x-`**, as for any open array of a `["VMS"]` routine; a
     value `DESC` parameter is refused, with the message that says to
     declare it `x-` or `VAR`. An `x-` actual that is not a variable (a
     constant array) is copied to the frame first, as `x-` does now.
   - **`NIL` omits it**, a longword 0, as for any parameter passed by
     reference or descriptor.
   - **Refused elsewhere**: in a `["C"]` or Oberon declaration, in a
     procedure type a callback is declared with (VMS would hand an
     Oberon procedure a descriptor it cannot read as an open array), and
     on a formal that is not an array, each a compile-time error.
     `-strict` already refuses a `["VMS"]` declaration, so `DESC` with
     it.

2. **The descriptor poc builds**, for `DESC ARRAY OF T`, an actual
   `a` of `LEN(a)` = n elements of `SIZE(T)` bytes each, 36 bytes:

   | Field | Value |
   |---|---|
   | `DSC$W_LENGTH` | `SIZE(T)`, or 0 if that exceeds 65,535 (as the standard allows; `ARSIZE` still holds) |
   | `DSC$B_DTYPE` | from `T`, proposal 3 |
   | `DSC$B_CLASS` | 4, `DSC$K_CLASS_A` |
   | `DSC$A_POINTER` | `ADR(a[0])` |
   | `DSC$B_SCALE`, `DSC$B_DIGITS` | 0 |
   | `DSC$B_AFLAGS` | `FL_COEFF` and `FL_BOUNDS` (`0C0X`): not `FL_REDIM`, since a callee cannot reallocate Oberon's array, and not `FL_COLUMN`, since Oberon is row-major |
   | `DSC$B_DIMCT` | 1 |
   | `DSC$L_ARSIZE` | n * `SIZE(T)` |
   | `DSC$A_A0` | `ADR(a[0])` again, the lower bound being 0 |
   | `DSC$L_M1` | n |
   | `DSC$L_L1`, `DSC$L_U1` | 0 and n - 1 (-1 for an empty array) |

   Always the full block, never the 16-byte prototype alone: a callee
   that reads only the prototype ignores the rest, and BASIC needs it,
   with both flags (tried 2026-10-26, below).

3. **The data type follows the element type**, the codes `DSCDEF`
   gives:

   | `T` | dtype |
   |---|---|
   | `SYSTEM.INT8`, `INT16`, `INT32`, `INT64` | `B` (6), `W` (7), `L` (8), `Q` (9) |
   | `SYSTEM.CARD8` to `CARD64`, `SYSTEM.ADDRESS`, `SET`, `SYSTEM.SET64` | `BU` (2), `WU` (3), `LU` (4), `QU` (5), by size |
   | `SHORTINT`, `INTEGER`, `LONGINT`, `HUGEINT` | the signed code of its size under the size model in force |
   | `BOOLEAN` | `BU` |
   | `REAL` | `F` (10) |
   | `LONGREAL` | `G` (27): poc's `LONGREAL` on the VAX is G_floating |
   | `CHAR` | `T` (14), for `ARRAY OF ARRAY OF CHAR` only (proposal 4) |
   | a record, a pointer, a procedure, anything else | `Z` (0), unspecified, with the length still `SIZE(T)` |

   A routine that wants D_floating (VAX BASIC's `/REAL=DOUBLE`) gets `G`
   from a `LONGREAL` array, and would read garbage; that is the
   program's to convert, as for a single real today (question 2).

4. **`DESC ARRAY OF ARRAY OF CHAR` is one dimension of strings**: n
   elements of dtype `T`, each `LEN(a, 1)` characters, which is what
   `SMG$CREATE_MENU` and `DescribeArray` mean, and is VMS's usual "array
   of fixed-length strings". The strings are passed as they lie: no `0X`
   is looked for, no blank padding added (the program pads, as the guide
   says now). A two-dimensional character array is not offered.

5. **Other arrays of arrays** (`DESC ARRAY OF ARRAY OF SYSTEM.INT32`)
   are refused at first, and allowed later if a routine needs them: a
   dimct of 2 or more, row-major, with `M1`..`Mk` the lengths and each
   `Li`, `Ui` 0 and `LEN(a, i-1) - 1`.

6. **Not in this proposal**: an array whose elements are descriptors
   (BASIC's `X$()`, dtype `DSC`). Each element would need a descriptor of
   its own, and BASIC's are `CLASS_D`, which the callee allocates and
   frees through `STR$`, so their lifetime is not the call's. A binding
   builds those by hand, in a record that holds the element descriptors,
   as the POISE binding does. A later proposal can take it up with
   `CLASS_D` strings, if ever.

7. **`VmsArguments`**: `DescribeArray` and `ArrayDescriptor` stay, for
   descriptors a program keeps past one call. `SMG_ROUTINES`'
   `SMG$CREATE_MENU` and any other generated declaration whose SDL says
   "by descriptor, array" (the generator, part 2, now writes
   `SYSTEM.ADDRESS` for it) are regenerated with `DESC`, and the guide's
   menu example shrinks to the call.

## What it would touch

- **Front end.** The parser takes `DESC` before a formal type; the
  parameter records it (beside `VAR` and read-only), and the `.sym` file
  keeps it, so an importer passes the descriptor too: a symbol-file
  format change. `CheckVmsParameters` refuses it where proposal 1 does.
  Two procedure types are the same only if their parameters agree in
  `DESC` too (for `["VMS"]` procedure variables).
- **Backend** (`VaxCodeGenerator.Mod`). `VmsArgument` gains a case
  beside `StringDescriptor`: nine longwords in frame slots, the length,
  pointer, `ARSIZE`, `M1` and `U1` from the actual's address and `LEN`
  (known at compile time for a fixed actual, read from the hidden length
  for an open one).
- **Fixtures**: semantic accept and reject (both size models, through a
  `.sym`), the backend's `.mar`, and a guest run against a BASIC callee
  that prints what it was given (`LBOUND`, `UBOUND`, the sum), and
  against `SMG$CREATE_MENU`.
- **Documents**: `language-extensions.md` (the table), `AGENTS.md`'s
  summary, `vax-vms-guide.md` chapter 7 and the menu example,
  `vms-sdl-interfaces.md` (the generator), `rtl/vax/README.md`.

## Questions for the user

1. **The word.** `DESC`, as asked. Should it also be allowed before an
   open `ARRAY OF CHAR`, to say explicitly what is implicit now (still a
   `CLASS_S` descriptor, not `CLASS_A` of characters)? The proposal
   refuses it there, so there is one way to write each thing.
2. **D_floating.** Should a `LONGREAL` array be described as `G` and
   left at that, or should there be a way to say `D` (a
   `SYSTEM.DFLOAT`-like element type, which would also serve single
   reals)? Nothing in the POISE SPL needs a real array; a BASIC routine
   elsewhere might.
3. ~~**`FL_REDIM`.**~~ Settled on the guest, 2026-10-26 (below):
   BASIC does not need it, and `0C0X` stands.
4. **Scalars by descriptor.** A few routines take a number by a
   `CLASS_S` descriptor (`LIB$CVT_DX_DX`, some `OTS$`). Should `DESC`
   before a scalar formal mean that, later? Not proposed now.

## Tried on the guest: the flags BASIC needs (2026-10-26)

Question 3, run as `POC2` (POISE binding, `experiments/exp06`). An
Oberon program built the full 36-byte descriptor by hand, varying only
`DSC$B_AFLAGS`, and passed it to two VAX BASIC subs (`SUB NUMTEST(A%())`,
which sums the elements between `LBOUND` and `UBOUND` and sets the last;
`SUB STRTEST(S$())`, which prints two `CLASS_D` elements and assigns one)
and to the SPL's `UTL_STRIP_QUALS`. Each call was under `LIB$SIG_TO_RET`.

| aflags | Result |
|---|---|
| `0D0X` (BASIC's own: `REDIM`, `COEFF`, `BOUNDS`) | all three right: bounds 0 to 5, sum 75, the last element set to 99; `S$(1)` set; `FILE`, found 3, `X.LIS` |
| `0C0X` (`COEFF`, `BOUNDS`) | the same, in every detail |
| `080X` (`BOUNDS`), `040X` (`COEFF`), `0X` | every call signals `BAS-F-ARGDONMAT`, "Arguments don't match" (`%X001A82C4`); nothing changed |
| `0C0X` with `M1` 0 and `U1` 2 (wrong) | BASIC believes the bounds: `NUMTEST` sees 0 to 2 (sum 33) and `ARSIZE` is not checked against them; `UTL_STRIP_QUALS` signals `BAS-F-SUBOUTRAN` |

So proposal 2's `0C0X` is right: `FL_REDIM` is not needed, and `FL_COEFF`
and `FL_BOUNDS` are both required. BASIC takes the bounds from `L1` and
`U1`, so they must be exact. (A sub that signalled part-way through a
`PRINT` left its partial line in BASIC's output buffer, printed in front
of the next line: a cosmetic quirk of the run, not of the descriptor.)
