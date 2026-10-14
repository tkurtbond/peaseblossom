# VMS interface modules from SDL (Phase 17 step 5)

`PLAN.md` Phase 17 step 5 asks whether a tool generates poc's Oberon
modules for VMS's own definitions - status codes, function codes,
control-block layouts, the `SYS$`, `LIB$` and other routines - and names
the user's UNSDL utility as the likely starting point. This is the first
look at that utility and the guest (2026-10-11), with the user's
decisions the same day. The step's design and proposals come later, when
Phase 17 begins; nothing here is built yet.

## What UNSDL is

UNSDL (`~/Repos/myunsdl`, 1988-1990, VAX C; its `aaareadme.txt` and
sources) is a set of *language back ends* for SDL, not a parser of SDL
source. VMS keeps STARLET's definitions, written in SDL, already parsed:
SDL's intermediate files (`.SDI`) are the modules of the text library
`SYS$SHARE:STARLETSD.TLB`. `SDL/NOPARSE/LANGUAGE=<x> <file>.SDI` reads one
into a tree in memory, maps in the shareable image `SDL$SHARE:SDL<x>.EXE`,
and calls its `sdl$output(outputname, module, root)`; the back end walks
the tree and writes the declarations for its language.

- `unsdl.c` is a driver with its own verb, `UNSDL` (`unsdl.cld`):
  `UNSDL <file>/LANGUAGE=<x>=<options>/OUTPUT=<file>` puts the options in
  a DCL symbol (`SDL_COMMAND_ARGS`), which `SDL/NOPARSE` has no way to
  pass, and then runs `SDL/NOPARSE/LANGUAGE=<x>=<output> <file>` itself
  through `LIB$DO_COMMAND`. It is a front end to `SDL/NOPARSE`, not a
  replacement: SDLNPARSE still reads the `.SDI` file and calls the back
  end.
- `sdlcc.c` writes C headers; `sdlscm.c` writes Scheme (constants as
  `(define ...)`, entries as `(define-foreign ...)` with each parameter's
  type, direction, mechanism and optionality; it does not render
  aggregates); `sdldump.c` dumps the tree. Each is linked `/SHARE` with
  `misc.c`, `readable.mar` (`PROBER`, to test a pointer before following
  it) and, for the options, a CLD.
- `sdldef.h` is the tree, worked out by reading it (some fields are
  marked "???"): node kinds root, comment, constant, entry, item (a field
  or aggregate), module, parameter and head (each list's head); each node
  a name, prefix and tag, an offset, a field size, low and high
  dimensions, a data type (address, byte, character, boolean, decimal, D,
  F, G and H floating, longword, octaword, quadword, bit field, word,
  structure, union, any, entry, the complex types) and flags (value,
  mask, unsigned, based, descriptor, dimension, in, out, reference, fill,
  optional, list, RTL string descriptor, and others); a constant's value
  is its `typeinfo`, a character item's length too.
- `all4.com` and `all5.com` extract about 30 of the library's modules
  with `LIBRARY/EXTRACT` and run UNSDL on each.

## What the guest has (2026-10-11, `tools/vax-do`)

- `SYS$COMMON:[SYSLIB]STARLETSD.TLB;10`, created 9-JUL-1993 (the
  5.5-2H4 kit), 65 modules: `STARLET` (the `SYS$` services);
  `STARDEFAE`, `STARDEFFL`, `STARDEFMP` and `STARDEFQZ` (the `$xxxDEF`
  definitions, alphabetically in four parts); `RMSDEF` and `RMSUSR`; the
  routines of `LIB$`, `STR$`, `SMG$`, `OTS$`, `MTH$`, `DTK$`, `PPL$`,
  `SOR$` and `NCS$`; `SSMSG` and the other `*MSG` modules of status
  codes; `SMGDEF`, `LIBCLIDEF`, `LBRUSR`, `OBJFMT`, `VAXDEF` and others.
- `SYS$COMMON:[SYSEXE]SDLNPARSE.EXE`, and the `SDL` verb in the
  system's DCL tables: `SDL/NOPARSE` works for `POC` as for any user (the
  user's session showed it first; `POC`'s `SDL/NOPARSE NLA0:` ended with
  success). `SDL$SHARE` is not defined, as `sdl.rno` expects: it is a
  logical name the user of a back end defines to point at the directory
  holding the back ends (`DEFINE SDL$SHARE DISK:[DIR]`), since SDLNPARSE
  finds one by `LIB$FIND_IMAGE_SYMBOL("SDL$SHARE:SDL<x>", "SDL$OUTPUT")`.
  UNSDL and its back ends should therefore run on the guest as they are.
- VAX C 3.2, which builds the back end.

## Decided (the user, 2026-10-11)

- **The generator runs on the VAX** and is built with **VAX C**. poc and
  its runtime still use none of the layered products (Phase 16 step 1);
  the generator is a tool run when the modules are made, and what it
  writes is committed.
- **Not on the host**: a `.SDI` file is kept in one of VMS's record
  formats inside a text library (`STARLETSD.TLB` is in DCX data-reduced
  format), and the tree is SDLNPARSE's in-memory one, which nobody has
  documented as a file; reading either away from RMS and the Librarian
  is not worth it.

## What poc needs

1. **A back end of its own, `SDLOBERON`**, written as `sdlscm.c` and
   `sdlcc.c` are, that writes one poc module for each SDL module (for
   example `SsMsg`, `IoDef`, `LibRoutines`):
   - a constant as `CONST SS$_NORMAL* = 1;`, a mask in hexadecimal; the
     names are the system's, which poc allows (`AGENTS.md`, "Underscores
     and dollar signs in identifiers");
   - an entry as `PROCEDURE ["VMS", "SYS$QIOW"] ...;`;
   - exact-width types only, `SYSTEM.INT8/16/32/64` and
     `SYSTEM.ADDRESS`, so that a module means the same under `-O2` and
     `-OC`; F_floating as `REAL` and G_floating as `LONGREAL`, which are
     poc's VAX formats; D_floating, which poc has no type for, as 8
     bytes, H_floating and an octaword as 16;
   - a banner naming the library, its version and SDL's, so that a
     module says which kit it came from.

2. **What the language and the VAX backend lack**, which is most of the
   step, since the generator can only write what poc accepts:
   - *Passing mechanisms*. A `["VMS"]` external now passes a value of 4
     bytes or less by value and a `VAR` parameter by reference
     (`vax-macro32-backend.md`, section 7); a descriptor is an error.
     SDL marks each parameter value, reference or descriptor (or RTL
     string descriptor), so a declaration needs a way to say which.
   - *Optional parameters*, which most `SYS$` services have and Oberon
     does not. One convention: an optional parameter passed by
     reference is declared `SYSTEM.ADDRESS`, and 0 omits it.
   - *Record layout*. VMS lays out a structure with no alignment (VAX
     C's rule, which VMS's languages follow), and poc aligns a field to
     its size up to 4 bytes (`vax-macro32-backend.md`, section 4,
     decided). Its records match a VMS structure only with a
     packed-record attribute, which that section left to this phase;
     without one, a structure is an array of bytes and its fields
     offset constants (`FAB$L_FNA`).
   - *Unions and bit fields*, which an Oberon record cannot express
     (`PLAN.md` says so). SDL already gives each bit field its position,
     size and mask (`$V_`, `$S_`, `$M_` constants), which a program can
     use with `SET`s and `SYSTEM`; a union's arms overlap, so one arm
     at most can be a record's fields.
   - *Item lists and descriptors* as types a program can fill, which
     the same step asks for.

## Proposals, part 1: how a `["VMS"]` declaration passes its arguments

Step 4 chose the interfaces (`doc/research/vms-native-library-inventory.md`,
approved 2026-10-14). Its proposal 7 puts step 5's mechanisms first,
since the generator can only write what poc accepts. This part is those
mechanisms. The generator's design is part 2, proposed once these work.

**Approved by the user, 2026-10-14**, all eight as written.

**What the calling standard requires.** The VAX Procedure Calling
Standard passes an argument by immediate value, by reference or by
descriptor. Each language must give the caller "explicit control ... of
the argument-passing mechanism for the data types supported by the
language" (*Introduction to VMS System Routines*, 5.4, `AA-LA66B`,
2.3.2.2):

| Data type | By value | By reference | By descriptor |
|---|---|---|---|
| Atomic, 32 bits or less | yes | yes | yes |
| Atomic, more than 32 bits | no | yes | yes |
| String | no | yes | yes |
| Array | no | yes | yes |

An omitted optional argument and a null argument are both a longword 0
in the argument list. "The programming language syntax required to
produce argument list entries containing 0 differ from language to
language" (1.2).

**How the DEC languages do it** (the same manual):
- FORTRAN marks each argument at the call: `%VAL(x)`, `%REF(x)`,
  `%DESCR(x)` (2.3.2.2).
- Pascal and Ada say it in the declaration. Pascal's `char_string` is
  `[CLASS_S] PACKED ARRAY [L..U:INTEGER] OF CHAR`, which "accepts VARYING
  OF CHAR or PACKED ARRAY OF CHAR and produces the CLASS_S descriptor
  required by system services" (Table A-10). Ada's is `STANDARD.STRING`
  (Table A-2).

poc follows Pascal and Ada: the declaration says it once, so a call is
written as any Oberon call is.

**What poc does now** (`vax-macro32-backend.md`, section 7):
- A value parameter of 4 bytes or less is passed by value.
- A `VAR` parameter is passed by reference.
- Everything else is refused: an array, record or quadword value
  parameter, an open array, a descriptor.

`rtl/vax`'s 69 `["VMS"]` declarations use only those two. Every
character array among them is a fixed-length `VAR name: Name`, passed by
reference, and none has an open array or a read-only parameter. So each
rule below gives a meaning to something refused today, and changes no
existing call.

1. **The mechanism follows the formal parameter, in a `["VMS"]`
   declaration only.** No new syntax:

   | Formal parameter | Passed | VMS's words |
   |---|---|---|
   | value, a scalar, `SET`, pointer or procedure of 4 bytes or less | by value, as now | "by value" |
   | `VAR x: T`, `T` not an open `ARRAY OF CHAR` | by reference, as now | "by reference, write only" or "modify" |
   | `x-: T`, any `T` but an open `ARRAY OF CHAR` | **by reference, always** | "by reference, read only" |
   | `ARRAY OF CHAR` (open), value, `x-` or `VAR` | **by a `CLASS_S` string descriptor** | "by descriptor" |
   | open `ARRAY OF T`, `T` not `CHAR`, `VAR` or `x-` | **by reference**, the address of element 0 | "by reference, array reference" |
   | value parameter of an array, record or quadword type | an error, as now, saying to declare it `x-` or `VAR` | |

   - **Explicit control, as 2.3.2.2 asks**, comes from choosing the
     formal:
     - A fixed `ARRAY n OF CHAR` or an `ARRAY OF SYSTEM.BYTE` passes a
       string by reference.
     - A `SYSTEM.ADDRESS` value passes any address: `SYSTEM.ADR(x)`, or a
       descriptor of another class built in a record (proposal 6).
   - **`x-` changes meaning here.** In an Oberon procedure, a read-only
     parameter of at most 16 bytes is passed by value
     (`language-extensions.md`, "Read-only parameters"). In a `["VMS"]`
     declaration it is always by reference, since VMS's "by reference,
     read only" is exactly that. It takes any actual, as it does now: a
     variable, a constant or an expression, which poc puts in a
     temporary. So a quadword time or a longword item code can be
     written as a constant.
   - Fixed-length `ARRAY n OF CHAR` stays by reference. `rtl/vax`'s
     `PocRtl` routines rely on that.

2. **A string descriptor is built by the caller, in its frame.**
   - It is 8 bytes: the length (a word), `DSC$K_DTYPE_T` (14),
     `DSC$K_CLASS_S` (1), and the address (Introduction 2.9.2).
   - **An input, a value or `x-` parameter**, describes the string up to
     its first 0X, or all of `LEN(a)` if there is none. A constant string
     is described at its own length. VMS sees the text, not Oberon's
     terminator.
   - **An output, a `VAR` parameter**, describes all of `LEN(a)`. VMS
     writes a fixed-length output blank-padded to that length (STR$
     manual 2.2), so it leaves no 0X. The program ends the string with
     the routine's resultant length (`a[n] := 0X` when `n < LEN(a)`), as
     the hand-written modules of step 4's proposal 4 do.
   - **Length limit:** a descriptor's length is a word. An array of more
     than 65,535 characters is described as its first 65,535.

3. **`NIL` omits an argument.** In a call of a `["VMS"]` procedure, `NIL`
   may be the actual for any parameter passed by reference or by
   descriptor, and is passed as 0, VMS's omitted or null argument.
   - A value parameter is omitted by passing 0 or `FALSE` itself, which
     is what VMS reads.
   - The other actuals are type-checked as now. So `NIL` is the only
     loosening, and a required argument passed `NIL` fails as VMS fails
     it (`SS$_ACCVIO` and the like). The generator (part 2) will say
     which parameters are optional in a comment.

4. **A procedure is passed by value, its entry mask's address.** That is
   what VMS calls "procedure value, by reference". A procedure type used
   for a parameter of a `["VMS"]` procedure must be one VMS can call:
   - its parameters are value parameters of 4 bytes or less, and `VAR`
     parameters of a type with no hidden argument (not a record, which
     carries its tag, and not an open array, which carries its lengths);
   - its result, if any, is a scalar of at most 8 bytes.

   poc checks this where the procedure type is used, and says which
   parameter breaks it.
   - **A synchronous callback** then works as it is: an Oberon procedure
     is entered by `CALLS`/`CALLG` through its entry mask with its
     arguments at `4(AP)` (`vax-macro32-backend.md`, section 14, item 7).
     The collector scans the stack conservatively (`rtl/vax/
     GarbageCollectedHeap.Mod`), so VMS's frames between the callback
     and the program do not hide a root. `LIB$TRAVERSE_TREE`'s action
     routine and `SOR$`'s comparison are such callbacks.
   - **An AST routine or condition handler** compiles under the same
     check, but runs asynchronously. Whether it is safe is step 6's
     question, and the documentation says so until then.

5. **No packed records.**
   - poc aligns a field to its size, up to 4 bytes
     (`vax-macro32-backend.md`, section 4). The structures a program
     builds most often already have their VMS layout under that rule:
     - the string descriptor: word, byte, byte, longword;
     - the `item_list_3` entry: word, word, longword, longword, 12 bytes;
     - the `item_list_2` entry: word, word, longword, 8 bytes;
     - the I/O status block: word, word, longword.
   - For the generated structures (RMS's blocks, the `$xxxDEF`s), part 2
     proposes that the generator compare each SDL structure's offsets
     with poc's layout of the same fields. It writes a `RECORD` where they
     agree, and an array of bytes with offset constants where they do
     not. A packed-record attribute is proposed only if a structure that
     matters does not fit.

6. **One hand-written module, `VmsArguments`, for the structures above.**
   - Types: `StringDescriptor`, `ItemListEntry3`, `ItemListEntry2` and
     `IOStatusBlock`, with exact-width fields (`SYSTEM.INT16/INT32`,
     `SYSTEM.ADDRESS`), so that they mean the same under `-O2` and `-OC`.
   - Procedures: `Describe(VAR descriptor, VAR text)` fills a descriptor
     for a string up to its 0X. `SetItem(VAR list, index, code, VAR
     buffer, VAR returnLength)` fills an item from a buffer's address and
     size. `EndList(VAR list, index)` writes the zero longword that ends
     a list.
   - An item list is then an `ARRAY n OF ItemListEntry3`, passed to a
     `VAR` or `x-` open-array parameter, by reference (proposal 1).
   - Step 4's `Conditions`, `LogicalNames` and `Symbols` are written over
     it.

7. **Left for later, each a compile-time error that says so:**
   - Variable argument lists (`LIB$SIGNAL`, `$FAO`): `Conditions` has
     fixed numbers of arguments (step 4, proposal 4), and `$FAOL` takes
     its parameters as an array, by reference.
   - Descriptors of other classes (`CLASS_D`, `CLASS_A`, `CLASS_NCA`,
     varying strings), except built by hand through `SYSTEM.ADDRESS`.
   - Function results passed through a hidden first argument: strings,
     D and H floating, complex.
   - JSB entries.

8. **What is checked, and where it is written down.**
   - **On the guest**, a new fixture, `vax-vms-calls`, calls real
     routines and checks each rule:
     - `LIB$SET_SYMBOL` and `LIB$GET_SYMBOL`: a string in and a string
       out, with the resultant length.
     - `$TRNLNM` with an item list, its `acmode` omitted by `NIL`.
     - `$GETJPIW` with an item list and an I/O status block.
     - `$BINTIM` and `$ASCTIM`: a quadword by reference, read only,
       written `x-`.
     - `LIB$INSERT_TREE` and `LIB$TRAVERSE_TREE`: a callback.
     - An `ARRAY OF SYSTEM.BYTE` by reference, through `$FAOL`'s
       parameter list.
   - **On the host:**
     - `semantic-vms-arguments` shows what is accepted.
     - `semantic-reject-vms-arguments` shows each error: a value record,
       `NIL` for a value parameter, a callback type with a `VAR` record
       parameter.
     - `vax-vms-arguments` has the MACRO-32 written for each mechanism,
       for the user's review.
   - **One check of what poc does now.** The standard leaves R0's high
     bits undefined for a result narrower than 32 bits (2.4). poc must
     extend such a result in the caller, not rely on the callee to have
     done it. This is checked and fixed if needed.
   - **The documents:**
     - `language-extensions.md`, "External procedures", gets the rules.
     - `AGENTS.md`'s summary of that section gets a line.
     - The Reference Guide's "External procedures" section gets an
       example.
     - The rules apply only inside `["VMS"]` declarations, which
       `-strict` already rejects, and the LLVM backend still refuses
       `["VMS"]`.

## Part 1 done: what was implemented (2026-10-14)

All eight proposals, as approved. What the text above left open, and
what was found:

- **Front end** (`SemanticActions.Mod`). A `["VMS"]` procedure's type is
  marked (`Types.ProcedureTypeDesc.isVms`), which a `.sym` file keeps,
  since an importer resolves the declaration again.
  - `CheckVmsParameters` refuses a value parameter that does not fit a
    longword (`MemoryLayout.Size` with the VAX's word, under the current
    size model, so a `LONGINT` under `-OC`). The error is at the
    declaration and names the parameter.
  - `CheckVmsCallbackType` checks a procedure-typed parameter (proposal
    4). Proposal 4 names value and `VAR` parameters only, so a read-only
    one is refused too, with its own message: an Oberon callee would
    take a small one by value, a large one by reference.
  - `CheckArguments` takes the word `NIL` for a `VAR`, read-only or open
    `ARRAY OF CHAR` parameter of a `["VMS"]` procedure. A constant
    declared `= NIL` is not taken so; only the word itself.
- **Backend** (`VaxCodeGenerator.Mod`). The three refusals "Phase 17
  chooses its mechanism" are gone. `VmsArgument` lowers each `VAR`,
  read-only and open-array argument of an external call, and
  `StringDescriptor` builds a descriptor in two frame slots. A
  temporary, a descriptor or a copy, is kept until `CALLG` returns,
  with the copies the HUGEINT arguments already had. A read-only scalar
  whose value was spilled to a slot keeps that slot too.
  - The input descriptor's `LOCC` overwrites `R0`-`R1`, so `R0` and
    `R1` are freed first, as before a call.
- **The check of narrow results** found nothing to fix: a result is
  claimed in `R0` at its own type, and every use reads that width
  (`CVTBL R0`, `CVTBW R0`, `CVTWL R0`, `BLBS R0`); nothing reads a narrow
  register as a longword. `vax-vms-arguments`' `NarrowResults` shows it.
- **`rtl/vax/VmsArguments.Mod`**: the four types and three procedures.
  Its words are made by `SYSTEM.VAL(SYSTEM.INT16, n)`, which truncates,
  since `SHORT` takes a `LONGINT` to a word under `-O2` but to a
  longword under `-OC`, and the module compiles under both. `SetItem`'s
  index and code are `LONGINT`s.
- **Fixtures**:
  - `vax-vms-calls` passed on its first run on the guest: the symbol in
    and out (length 8, local table), `$TRNLNM` of a process logical name,
    `$GETJPIW`'s user name `POC` with I/O status 1, `$BINTIM` and
    `$ASCTIM` both ways and a delta time from a constant, the tree
    `1 2 5 8` from keys 5, 2, 8 and 1 through `CompareKey`,
    `AllocateNode` and `ShowNode`, and `$FAOL`'s `42 and 000000FF`.
  - `semantic-vms-arguments` (under `-O2` and `-OC`, and through
    `VmsServices`' `.sym`), `semantic-reject-vms-arguments` (both
    models; `NIL` to a `["C"]` procedure's `VAR` parameter is refused
    still) and `vax-vms-arguments` (`expected-vax.mar` and
    `expected-vax-VmsArguments.mar`, reviewed by the user 2026-10-14).
  - Changed: `vax-emit-errors` (`VaxTooMuch`'s open array passed to an
    external is lowered now), `vax-build` (its `-OC` build is refused by
    the front end, its `LONGINT` value parameter a quadword) and
    `vax-library` (26 modules, 542 universal symbols).
- **Documents**: `language-extensions.md`, "External procedures", has the
  rules in a subsection, `AGENTS.md` a summary, the Reference Guide an
  example, `vax-macro32-backend.md` sections 7 and 14 a pointer here,
  and `rtl/vax/README.md` the module.
