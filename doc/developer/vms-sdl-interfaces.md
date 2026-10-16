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
  UNSDL and its back ends should therefore run on the guest as they are
  (wrong: 5.5-2's SDLNPARSE looks only in `SYS$SHARE`; part 2).
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

## Proposals, part 2: the generator

Part 1 made the mechanisms the generator writes. This part is the
generator itself: where it runs, what it reads, and what Oberon it
writes for each kind of SDL node. Step 4's proposals 1 and 2 decided
that all of `STARLETSD.TLB` is generated, as a faithful transcription:
the system's names, SDL's mechanisms, constants and structures.

**What was found on the guest first (2026-10-14).**

- **`SDLNPARSE` loads a back end only from `SYS$SHARE`.** The user's
  `sdldump` (`~/Repos/myunsdl`) builds and links as it is. But
  `SDL/NOPARSE/LANGUAGE=DUMP` failed with `%SDL-E-INVSHRIMG, Shareable
  language image not found DUMP`:
  - with `SDL$SHARE` defined in `POC`'s process as `SYS$DISK:[]`,
    `DUA1:[USERS.POC]` or `SYS$SCRATCH:`;
  - and with `SDL$SHARE` defined system-wide in executive mode as
    `DUA1:[USERS.POC.SDL]`, by the user.
  - A test program's `LIB$FIND_IMAGE_SYMBOL("SDLDUMP", "SDL$OUTPUT",
    ..., "SDL$SHARE:.EXE")` finds the same image, so the image is sound.
  - Once the user copied `SDLDUMP.EXE` to `SYS$SHARE` (`SYS$COMMON:
    [SYSLIB]`), the dumps worked. So this version (SDL V3.2-12,
    `SDLNPARSE.EXE` of 17-OCT-1991) looks only there, and the first
    section's "should run on the guest as they are" was wrong.
- **No other renderings show the mechanisms.**
  - `SYS$LIBRARY:STARLET.H` declares each service with no parameters
    (`long int sys$qiow() ;`).
  - `STARLET.REQ`'s BLISS keyword macros give the order and the
    defaults (`EFN=0, CHAN, FUNC, IOSB=0 ...`), but not the mechanisms.
  - Only the tree has them.
- **VAX C's headers, `SYS$LIBRARY:VAXCDEF.TLB`** (30-NOV-1990, 208
  modules), are SDL's own C output. There is one header for each SDL
  `MODULE` node: `IODEF`, `JPIDEF`, `SSDEF`, `FAB` (`MODULE $fabdef`),
  `LIB$ROUTINES`. The FAB shows SDL's common shape: a union of a
  scalar and a structure of bit fields (`fab$r_fop_overlay`: `fab$l_fop`
  and `fab$v_asy ...`), and an address of another structure (`struct
  NAM *fab$l_nam`).
- **An `x-: ARRAY OF SYSTEM.BYTE` formal takes only byte arrays today**
  ("argument is not array compatible"). A `VAR` one takes any variable
  (`Oberon2.pdf`, Appendix C).

**What the dumps show (2026-10-14).** `SDLDUMP` was run on seven of
`STARLETSD.TLB`'s modules: `SSMSG`, `STARLET`, `LIB$ROUTINES`,
`STR$ROUTINES`, `STARDEFFL`, `RMSDEF` and `RMSUSR`. `sdldef.h`'s node
layout of 1988 reads 5.5-2's trees correctly. What the generator must
follow:

- **Module nodes.** A library module holds one or more SDL `MODULE`
  nodes: `STARDEFFL` has 17 (`$FACDEF`, `$FIBDEF`, `$IODEF`, `$JPIDEF`,
  ... `$LPDEF`), `RMSUSR` has 19 (`$FABDEF`, `$RABDEF`, `$NAMDEF`, the
  `$XAB...DEF`s, `$FSCNDEF`, `$RMEDEF`), and `SSMSG`, `STARLET`,
  `LIB$ROUTINES` and `STR$ROUTINES` one each (`$SSDEF`, `STARLET`,
  `lib$routines`, `str$routines`). The names come in either case.
  `RMSDEF` holds only RMS's status codes; the structures are in `RMSUSR`.
- **Constants.** Each has its full name (`SS$_NORMAL`) and its value
  (`typeinfo`; none means 0).
  - A `$M_` mask is a constant node with the `mask` flag. Three have
    bit 31 set (`LKI$M_SYSNAM`, `LMF$M_LOOKUP_LICENSE_SPARE`,
    `LP$M_PAGE_L`).
  - Some other constants are negative (`KGB$K_*`, 8000000xH; `JPI$_CHAIN`,
    -1).
  - `$V_`, `$S_` and the field-offset constants are not nodes. SDL's
    MACRO back end computes them from the items, and so must this one.
- **Items** (an aggregate's members).
  - An offset is from the start of the outermost aggregate; `fldsiz` is
    the size in bytes, a dimensioned field's whole size (`dimen`,
    `hidim`).
  - A bit field's offset is its enclosing structure's, and its `fldsiz`
    is its width in bits. Its position is the sum of the widths of the
    bit fields before it in that structure: this gives every one of the
    543 masks in `STARDEFFL` and `RMSUSR`.
  - A union is an overlay. 62 unions lead with a scalar as large as the
    union (`FAB$R_FOP_OVERLAY`: `FAB$L_FOP`, then a structure of bit
    fields); 2 lead with a structure that fills the union and holds
    fields (`FIB$R_FUNCDEPEND`, `LKI$R_NAMSPACE_UNION`); 1 has no member
    that fills it with fields (`LAT$R_ESTATFLAGS`), and in 1 the member
    that fills it is not the first (`LAT$R_ITEM_VALUE`: a 2-byte counted
    string, then a longword).
  - 8 aggregates are top-level unions of bit structures (`IODEF`,
    `LCKDEF`, `XABPRODEF`, ...) and 7 are structures of bit fields only:
    they exist to give `$V_`/`$M_` constants.
  - Fields are named `FAB$L_FOP`, fillers `FABDEF$$_FILL_7` or
    `FAB$V_fill_0`. An aggregate is named `FABDEF`, with prefix `FAB$`.
  - Two scalars are not at their natural alignment, both longwords:
    `XAB$L_RVB` at offset 14 of `XABKEYDEF`, and `LAT$R_ITEM_VALUE`'s
    `LAT$L_ITEM_SCALAR_VALUE` at offset 2 of `ITEM_ENTRY` (`$LATDEF`).
- **Entries.** `STARLET` has 254, `LIB$ROUTINES` 162, `STR$ROUTINES` 32.
  - **An optional parameter** carries the flag `default` in `STARLET`
    and `optional` in the `LIB$`/`STR$` modules.
  - **A variable argument list** is the entry's flag `variable`: only
    `SYS$FAO` (its last parameter's type name is `VARYING_ARG`).
  - **Type names** are VMS usages: `EF_NUMBER`, `ITEM_LIST`,
    `IO_STATUS_BLOCK`, `DATE_TIME`, `CHAR_STRING`, `PROCEDURE`, ...
  - **Character parameters**: by `descriptor`; by reference with flag 26
    (`sdldef.h`'s "RTL string descriptor", on the `LIB$`/`STR$` ones),
    which is a descriptor too; and plainly by reference in 6 (the
    characters' address, their length another argument, as
    `LIB$CVT_DTB`'s, or one character, `STR$DUPL_CHAR`'s).
  - **A routine argument** (`ASTADR`, `ACTRTN`, `user_procedure`) is an
    `address` parameter whose object is an `entry` node. `STARLET` marks
    it by reference, `LIB$` by value; the argument list holds the
    routine's address either way (the calling standard's procedure
    value). `LIB$DECODE_FAULT`'s is by descriptor.
  - **Other parameters**: longwords, words and bytes by value or
    reference; arrays of them (`dimen`); quadwords (times, lock IDs),
    `any` (an item list, a FAB, `SYS$QIOW`'s P1 buffer, which it writes
    though SDL says `IN`) and structures by reference; addresses by value
    or reference; F and G floating by reference. None is D, H or complex.
  - **Results**: every `SYS$` service a longword; `LIB$` 149 longwords,
    9 none, 2 addresses (`LIB$ESTABLISH`), a word (`LIB$LEN`) and a
    boolean (`LIB$AST_IN_PROG`); `STR$` 31 longwords and a word.
  - 29 entries carry the flag `link`, among them every RMS service
    (`SYS$OPEN` ...), which take `ERR` and `SUC` routines. The `.REQ`
    and C renderings call them as any other, so the generator ignores it.

**Proposals.**

1. **The generator is a back end, `SDLOBERON`, which runs from
   `SYS$SHARE`.** `POC` builds it in `DUA1:[USERS.POC.SDL]`, and the user
   copies it to `SYS$SHARE` (protection `W:RE`), as with `SDLDUMP`: once
   for each rebuild. The executive-mode `SDL$SHARE` is not needed, and the
   user may deassign it.

2. **Where it lives and how it runs.**
   - `tools/sdloberon/`: `sdloberon.c`, written as `sdlscm.c` is, and
     copies of `sdldef.h` and `readable.mar` from `~/Repos/myunsdl`,
     with a note saying where they came from. `sdldump.c` goes there too,
     as the tool for looking at a tree.
   - `tools/vax-sdl`, a host script over `tools/vax-do`. It sends the
     sources and builds the back end with VAX C (the user then copies it).
     Run again, it extracts each `STARLETSD.TLB` module, runs
     `SDL/NOPARSE/LANGUAGE=OBERON` on it, and brings the `.Mod` files
     back.
   - The output is committed under `rtl/vax/vms/`. A user of poc never
     runs the generator; the user reruns it only for another kit.
   - The modules make a VAX library of their own, `VMSDEF` (`poc
     -library`, Phase 17 step 1), not part of `POCRTL`. Most have no
     code, and `POCRTL` stays the runtime.

3. **One Oberon module for each SDL `MODULE` node**, as VAX C has one
   header for each.
   - So `STARDEFFL`'s `$IODEF`, `$JPIDEF` and the rest are separate
     modules, and `RMSUSR` gives `FABDEF`, `RABDEF`, `NAMDEF` and the
     `XAB`s.
   - **The name is the node's, upper case, with a leading `$` dropped
     and any other `$` made `_`**: `IODEF`, `SSDEF`, `FABDEF`,
     `STARLET`, `LIB_ROUTINES`, `SMG_ROUTINES`. A file name with `$`
     needs quoting in a Unix shell.
   - None of these names differs only in case from a runtime module.
   - Each module starts with a banner: the library module and SDL node,
     `STARLETSD.TLB`'s creation date (9-JUL-1993), SDL's version, and
     "generated by tools/sdloberon; do not edit".

4. **Constants** are written as `CONST` with the system's name
   verbatim: `SS$_NORMAL* = 1;`.
   - A mask is written in hexadecimal. One with bit 31 set uses the
     16-digit pattern (`0FFFFFFFF80000000H`, `AGENTS.md`, "Hexadecimal
     constants as 64-bit patterns"), so that it is the negative
     longword VMS means and fits a `SYSTEM.INT32`.
   - Any other constant is decimal, a negative one included.
   - A string constant is a string.
   - SDL's comment on a constant goes after it, as an Oberon comment.

5. **Structures.** Every field gets its offset constant, as MACRO's
   `$xxxDEF` gives it: `FAB$L_FOP* = 4;`. A bit field gets `$V_` (its
   position, from the widths before it), `$S_` (its width) and, from
   SDL, `$M_`: `FAB$V_GET`, `FAB$S_GET`, `FAB$M_GET`. Fillers get none.
   Then the aggregate is laid out as a list of fields:
   - **A union** gives its first member that fills it: a scalar or an
     array of scalars is one field (`FAB$L_FOP`, `FIB$W_FID`); a
     structure holding fields gives those fields (`FIB$R_FUNCDEPEND`).
     The other members appear only as constants. A union with no such
     member is `ARRAY size OF SYSTEM.BYTE`, named after the union.
   - **A nested structure** gives its fields in place.
   - **Bit fields** outside a union's scalar are `ARRAY n OF SYSTEM.BYTE`
     over the bytes they cover, named after the first one.
   - **A scalar that is not at its natural offset** (`XAB$L_RVB`) is
     `ARRAY size OF SYSTEM.BYTE`, with a comment giving its type, and is
     used through `SYSTEM.GET`/`SYSTEM.PUT` and its offset constant.
   - **A filler** is a field named `fill<n>`, not exported, so that
     every byte keeps its place.
   - An aggregate that is a union, or holds only bit fields, gives only
     constants: no type.

   The `RECORD` is then written, named as the aggregate (`FABDEF.FABDEF`;
   VAX C's `struct FAB` is a name the C back end makes, and SDL's own is
   `FABDEF`), with fields of the system's names (`FAB$L_FOP`).
   - The generator checks that poc's layout (each field aligned to its
     size, at most 4: `MemoryLayout`) puts every field at SDL's offset.
     With the rules above, all 52 aggregates of `STARDEFFL` and `RMSUSR`
     pass, but one differs at the end: `XABDEF1` is 23 bytes, which poc
     pads to 24. Such a record is still written, with a comment, since
     VMS reads only its own bytes. One that fails anything else is
     written as `ARRAY size OF SYSTEM.BYTE` with a comment saying which
     field breaks it, and the generator reports it.
   - The field types are part 1's exact widths: byte `SYSTEM.INT8`, word
     `SYSTEM.INT16`, longword `SYSTEM.INT32`, quadword `SYSTEM.INT64`,
     address `SYSTEM.ADDRESS`, F `REAL`, G `LONGREAL`.
   - Characters are `ARRAY n OF CHAR`. A dimension is `ARRAY n OF T`.
   - D floating is `ARRAY 8 OF SYSTEM.BYTE`; H floating, an octaword and
     decimal are their size in bytes.
   - `unsigned` is noted in a comment, since poc has no unsigned types.
   - SDL's boolean is a byte, `SYSTEM.INT8`, since VMS tests only its low
     bit and an Oberon `BOOLEAN` must be 0 or 1.

6. **Entries.** `PROCEDURE ["VMS", "SYS$QIOW"] SYS$QIOW*(...): SYSTEM.INT32;`,
   with the entry's own name, upper case. Each parameter by part 1's
   rules, `x-` when SDL says `IN` and `VAR` when `OUT` or `IN OUT`:

   | SDL parameter | Oberon formal |
   |---|---|
   | a longword, word, byte or boolean by value | a value of that width; a boolean `SYSTEM.INT8` |
   | the same by reference | `x-` or `VAR x` of that width |
   | the same with a dimension | `x-` or `VAR x: ARRAY OF` that width |
   | characters by descriptor, or by reference with flag 26 | `x-` or `VAR x: ARRAY OF CHAR` (part 1's descriptor) |
   | characters by reference, no flag 26 | one character `x-: CHAR`, else `x-` or `VAR x: ARRAY OF SYSTEM.BYTE` |
   | a quadword, octaword, `any` or structure by reference | `x-` or `VAR x: ARRAY OF SYSTEM.BYTE`; since 2026-10-15 a quadword in is `x-: HUGEINT` (below, "Part 2 so far") |
   | F or G floating by reference | `x-` or `VAR x` of `REAL` or `LONGREAL` |
   | an address by value | `x: SYSTEM.ADDRESS` |
   | an address by reference | `x-` or `VAR x: SYSTEM.ADDRESS` |
   | `any` by value | `x: SYSTEM.ADDRESS` |
   | a routine (an address of an entry) | `x: SYSTEM.ADDRESS` now; a procedure type in step 6 |
   | anything by another descriptor, or characters whose type names an array (part 7, proposal 2) | `x: SYSTEM.ADDRESS`, a descriptor built by hand |

   - The quadword row lets one formal take a `HUGEINT`, an
     `IOStatusBlock`, a FAB or an item list (proposal 7). `SYS$QIOW`'s
     `P1`, which SDL calls `IN`, is written `VAR` when the generator is
     told so by a short list of known exceptions in `sdloberon.c`, with
     a comment; otherwise `x-` still passes a variable's own address,
     so a read works.
   - A routine is `SYSTEM.ADDRESS` until step 6 decides how an Oberon
     procedure is given to VMS (part 1's `CheckVmsCallbackType` already
     checks a procedure type). Until then `SYSTEM.VAL(SYSTEM.ADDRESS, P)`
     gives its address; `SYSTEM.ADR(P)` does not ("SYSTEM.ADR requires a
     variable"), as this said until 2026-10-15. Step 6 decided
     (`vax-macro32-backend.md`, section 22.3, proposal 1): an AST
     routine parameter is an `AsynchronousTraps.Routine`, and the other
     routine parameters stay `SYSTEM.ADDRESS`.
   - **An optional parameter** (`default` or `optional`) is marked in a
     comment: `(* optional: NIL omits it *)`, or for a value "0 omits
     it". Every argument is still written, as Oberon requires.
   - **The type name** (`EF_NUMBER`, `IO_STATUS_BLOCK`, ...) and SDL's
     comment go in a comment after the formal.
   - **A name that is an Oberon keyword** (`IN`, `TO`, `SET`, `END` ...)
     gets a trailing `_`; `LIB$`'s lower-case names stay as they are.
     A predeclared name may be redeclared and is kept.
   - **Entries left out**, each with a comment saying why (part 1,
     proposal 7): `SYS$FAO`, the one variable argument list, and any
     entry with a parameter or result no rule covers. None of the three
     modules dumped has another.
   - **Results**: a longword is `SYSTEM.INT32`, a word `SYSTEM.INT16`, an
     address `SYSTEM.ADDRESS`, a boolean `SYSTEM.INT8` (its low bit is
     the answer); none is a proper procedure.

7. **`x-: ARRAY OF SYSTEM.BYTE` takes any actual, in a `["VMS"]`
   declaration.** As a `VAR` one takes any variable, it takes a
   variable, a constant or an expression of any type. The address is
   the actual's, or a temporary's. This is SDL's quadword, `any` and
   structure by reference, read only. Outside `["VMS"]` nothing changes.

8. **What is checked.**
   - **On the host**, a fixture compiles every generated module under
     `-O2` and `-OC` and writes its `.mar`. A fixture builds the `VMSDEF`
     library on the guest, as `vax-library` does for `POCRTL`.
   - **Against VAX C's headers**, the independent rendering of the same
     SDL:
     - The generator also writes a C program that includes
       `VAXCDEF.TLB`'s header for the module and prints each constant
       and each field's offset (`offsetof`).
     - An Oberon program prints the same from the generated module.
     - A fixture compares the two on the guest.
     - The headers are from 1990 and the kit from 1993, so only names
       in both are compared, and the count of the others is reported.
   - **The generator's own checks**: the layout check of proposal 5, and
     each computed `$V_`/`$S_` against SDL's `$M_` (all 543 agree in the
     dumps).
   - **The supported tier** (step 4, proposal 3) keeps its own fixtures,
     each written when its group is done (step 4, proposal 7).
   - **The first output for review** is part of the work for this part:
     `SSMSG` (constants only), `$IODEF` and `$JPIDEF` (constants with
     masks), `$FABDEF` (a record with overlays), `$XABKEYDEF` (a
     misaligned field) and `STARLET`'s `SYS$TRNLNM`, `SYS$GETJPIW`,
     `SYS$QIOW` and `SYS$ASCTIM` (entries). The rest are generated once
     these are approved.

## Part 2 so far: what was implemented (2026-10-14)

The proposals above were **approved by the user, 2026-10-14**, and the
generator, proposal 7 and the checks were made the same day. The first
output is seven of `STARLETSD.TLB`'s modules: `SSMSG`, `STARLET`,
`LIB$ROUTINES`, `STR$ROUTINES`, `STARDEFFL`, `RMSDEF` and `RMSUSR`, 41
Oberon modules in `rtl/vax/vms`, **approved by the user, 2026-10-15**,
with the CARDs of part 3 and a quadword in as a `HUGEINT` (below); the
other 58 library modules follow.

- **The generator**, `tools/sdloberon/sdloberon.c` (VAX C), built and run
  on the guest by `tools/vax-sdl` (proposals 1 and 2). The user copies
  `SDLOBERON.EXE` to `SYS$SHARE`. `tools/sdloberon/sdlload.c` runs the
  same back end on atla over an `SDLDUMP` dump, which prints every node's
  address and links, so a change is tried before the guest.
- **`x-: ARRAY OF SYSTEM.BYTE` takes any actual** in a `["VMS"]`
  declaration (proposal 7): `SemanticActions.CheckArguments`, and
  `VaxCodeGenerator.VmsArgument`, which passes a variable's own address
  or a copy's in the frame. Fixtures `semantic-vms-arguments`,
  `semantic-reject-vms-arguments` and `vax-vms-arguments` (`PassBytes`).
- **The check against SDL's other rendering is `STARLET.MLB`, not VAX C's
  headers** (proposal 8 changed). The MACRO back end's `$xxxDEF` macros
  come from the same kit and define every constant the generator computes
  (`$V_`, `$S_`, offsets), where `VAXCDEF.TLB`'s headers, of 1990, hold
  only `$M_`, `$C_` and `$K_` and name no offsets or bits. Fixture
  `vax-vmsdef` assembles `$<M> GLOBAL` for each of the 38 `$xxxDEF`
  modules with a listing and compares its symbol table with the module
  (`compare-mlb.awk`, `expected-mlb`): **3587 names agree, none differs
  in value**. Four `$S_` of two `$LATDEF` aggregates are in `STARLET.MLB`
  only (`LAT$S_EFLAG`, `LAT$S_EFLAGBITS`, `LAT$S_ESTATFLAGS`,
  `LAT$S_ITM_CODE`), for nested unions that MACRO's back end sizes
  there and nowhere else; they are left out.
- **What the comparison corrected** (proposal 5): `$S_` is MACRO's rule,
  not every bit field's - a bit field's only when wider than a bit; a
  field's whose type does not give its size (more than one character, an
  array, a quadword); each aggregate's own (`FAB$S_FABDEF`), unless it
  is a filler.
- **Found in the trees, beyond the dumps' first findings**: a `LIB$` or
  `STR$` string parameter carries flag 26 *alone*, no reference or
  descriptor flag, and is a descriptor; a character parameter by
  reference with `typeinfo` -999 (`LENGTH *`) is the address of
  characters counted elsewhere (`LIB$CVT_DTB`), declared `x-: ARRAY OF
  SYSTEM.BYTE`; `STARLET` has one conditional (an `IFSYMBOL`, node type 13,
  which `SDLDUMP` prints as "unknown"): its `typeinfo2` is the
  condition, its child ring
  older forms of the DECdtm branch services (`SYS$ADD_BRANCH` ...) that
  the main ring declares again in their current form, so the generator
  leaves it out.
- **VAX C's `fputs` writes nothing of a string longer than 65535
  characters**: the guest's first `STARLET` and `LIB_ROUTINES` (190000
  and 93000 characters) came out empty, so the generator writes a
  module a line at a time. VAX C's `isprint` also passes Latin-1 (a `©`
  in `SSDEF`); comments keep only ASCII.
- **`SYS$QIOW`'s `P1` stays `x-`** (proposal 6 allowed a list of
  exceptions to make it `VAR`): `x-` passes a variable's own address, so
  a read into a buffer works, and a write can take a string constant,
  which `VAR` would refuse. The list is empty.
- **Left out, each with a comment**: `SYS$FAO`, a variable argument list,
  and the `LIB$`/`STR$` entries with a `LIST` parameter: `LIB$SIGNAL`,
  `LIB$STOP`, `LIB$SYS_FAO`, `LIB$MATCH_COND`, `STR$CONCAT`,
  `STR$FIND_FIRST_SUBSTRING`.
- **Fixture `vax-vmsdef`**: each module compiled under `-O2` and `-OC`;
  the library `VMSDEF` made, and built on the guest with `POCRTL`;
  `VmsDefLayout`, written by `layout-check.awk`, checks poc's offset of
  each field of the 37 record types against its constant, and each size
  (0 errors); `VmsDefCalls` calls `LIB$`, `STR$`, `$TRNLNM`, `$GETJPIW`,
  `$BINTIM`, `$ASCTIM`, `$ASSIGN`, `$QIOW` and RMS's `$OPEN` and
  `$CLOSE` through the generated declarations, with a `FABDEF.FABDEF`
  that RMS fills in.
- **A quadword in** (an open question, **decided by the user,
  2026-10-15**): `x-: ARRAY OF SYSTEM.BYTE` took a constant's own bytes,
  so `-600000000` gave VMS 4 bytes, not a delta time, unless written
  `SYSTEM.VAL(HUGEINT, c)`. Such a quadword is now `x-: HUGEINT`, signed
  or unsigned, since a delta time is negative: a constant is converted
  and passed as an 8-byte copy, a `HUGEINT` variable by its address, and
  `NIL` still omits an optional one. A record no longer fits there. A
  quadword out stays `VAR x: ARRAY OF SYSTEM.BYTE`, for an I/O status
  block, and so does one whose type name is `DESCRIPTOR`
  (`LIB$ANALYZE_SDESC`'s), for a `StringDescriptor`. 41 parameters
  changed, in `STARLET` and `LIB_ROUTINES`; `VmsDefCalls` passes the
  delta time as a constant.

## Proposals, part 3: SDL's unsigned types as poc's CARDs (2026-10-14)

**Approved by the user, 2026-10-14**, all seven, with the recommendations
for 3 (a condition value stays `SYSTEM.INT32`) and 5 (an address SDL
declares as an unsigned longword stays `CARD32`).

poc has had unsigned types since 0.6.0 (`language-extensions.md`,
"Unsigned integer types"), on the VAX since `2c1802d`
(`vax-macro32-backend.md`, section 20). The plan agreed with the user on
2026-10-14 is that the generator declares every SDL-unsigned field and
parameter, value parameters too, as the CARD of its width, where part 2,
proposal 5 only noted `unsigned` in a comment.

Before writing these proposals, a scratch copy of the generator was run on
atla over dumps of the seven modules made that day; the unchanged
generator reproduces `rtl/vax/vms` exactly. The scratch copy changes 280
fields and 715 parameters: 409 by value, 145 `x-` and 161 `VAR`, 45 of
them open arrays. That is 122 `CARD8`, 177 `CARD16`, 682 `CARD32` and 14
`CARD64` declarations. All 41 modules compile under `-O2` and `-OC`.
`VmsDefCalls` gets 11 errors, which proposals 4 to 6 answer.

1. **Fields.** A byte, word, longword or quadword item that SDL marks
   `unsigned` is `SYSTEM.CARD8`, `CARD16`, `CARD32` or `CARD64`, and an
   array of them `ARRAY n OF` that. An SDL boolean stays `SYSTEM.INT8`,
   as part 2 says. The `(* unsigned *)` comment goes, since the type
   says it. Layout is unchanged, since each CARD has its signed twin's
   size.
2. **Parameters.** The same, whatever the mechanism: a value of that
   width, `x-` or `VAR` of it, or `ARRAY OF` it when open. A quadword or
   octaword by reference stays `ARRAY OF SYSTEM.BYTE` (part 2, proposal
   6), `any` by value stays `SYSTEM.ADDRESS`, and a boolean stays
   `SYSTEM.INT8`. A program then needs a CARD variable for a `VAR`
   unsigned formal: `VAR channel: SYSTEM.CARD16` for `SYS$ASSIGN`'s
   `CHAN`. A non-negative constant goes to a value or `x-` formal as it
   is.
3. **Results: a condition value stays `SYSTEM.INT32`.** SDL is not
   consistent here: `STARLET`'s 262 `COND_VALUE` results are not marked
   unsigned, while `LIB$`'s and `STR$`'s 156 `cond_value` results are.
   So that one `status` variable takes any routine's result, and compares
   with `SS$_` and `RMS$_` constants, as now, every result whose type
   name is a condition value stays `SYSTEM.INT32`. The 17 results whose
   type name is `longword_unsigned` or `word_unsigned` (`LIB$` routines
   returning a count or a value) are `CARD32` or `CARD16`, as proposal 2
   would make a parameter. *The alternative* is the flag alone, which
   gives `LIB$`'s and `STR$`'s statuses one type and `SYS$`'s another.
4. **`VmsArguments`, part 1's hand-written module, follows.** VMS's
   lengths and counts become CARDs, so that one variable serves an item
   list and a routine's unsigned length (`VmsDefCalls`' `length` goes to
   `LIB$GET_SYMBOL` and to `SetItem`).
   - `StringDescriptor`: `length: SYSTEM.CARD16`, `dataType` and `class:
     SYSTEM.CARD8`.
   - `ItemListEntry3` and `ItemListEntry2`: `bufferLength:
     SYSTEM.CARD16`. `itemCode` stays `SYSTEM.INT16`, since a chain code
     is negative (`JPI$_CHAIN = -1`, `LNM$_CHAIN = -1`).
   - `IOStatusBlock`: `status` and `count: SYSTEM.CARD16`. With a CARD,
     a status above 32767 compares equal to its constant.
   - `SetItem`'s `returnLength`: `VAR SYSTEM.CARD16`.
   - The comment's "one over 32,767 is negative to Oberon" goes.
5. **An address SDL declares as an unsigned longword stays `CARD32`.**
   `FAB$L_FNA`, `FAB$L_DNA`, `FAB$L_XAB`, `FAB$L_NAM` and others like
   them are longwords in SDL, not addresses; only their comments say
   "address". So the tree gives nothing to tell them apart, and the
   generator does not guess from comments. A program sets one with
   `SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(name))`. That is a new cost:
   now the field is a `SYSTEM.INT32`, which `ADDRESS` (4 bytes on the
   VAX under both size models) includes, so `fab.FAB$L_FNA :=
   SYSTEM.ADR(name)` works as it is. *The alternative* is a short list
   of such fields in `sdloberon.c`, declared `SYSTEM.ADDRESS`, as part
   2, proposal 6 allowed for exceptions; the list would have to be kept
   by hand as more of the 65 modules are generated.
6. **`VmsDefCalls` is updated to the new types.**
   - `length`, `usernameLength` and `channel` become `CARD16`.
   - `FAB$L_FNA` is set by `SYSTEM.VAL`.
   - CARD fields are printed with `Out.Card`, and `FAB$L_STS` by
     `SYSTEM.VAL(LONGINT, ...)` for `Status`.
   - It prints the same lines on the guest as now.
7. **Regenerated and checked as part 2 was.**
   - `sdloberon.c` is changed and tried on atla with `sdlload`.
   - `tools/vax-sdl build` rebuilds it on the guest. The user copies
     `SDLOBERON.EXE` to `SYS$SHARE`, and `tools/vax-sdl run` writes
     `rtl/vax/vms` from the guest. That must equal what `sdlload` made.
   - `vax-vmsdef` passes: the 3587 constants still agree with
     `STARLET.MLB`, `VmsDefLayout` finds 0 errors, and `VmsDefCalls` runs.
   - `vax-vms-arguments` and `vax-vms-calls`, which use
     `VmsArguments`, are updated where its types change.

## Part 3 done: what was implemented (2026-10-14)

- **The generator.** `sdloberon.c`'s `unsigned_type` gives a byte,
  word, longword or quadword that SDL marks unsigned the CARD of its
  width (proposals 1 and 2).
  - It applies to fields and arrays of them, and to parameters by value,
    `x-`, `VAR` and open.
  - Booleans, `any`, and a quadword or octaword by reference keep their
    types.
  - "unsigned" stays in a comment only where the type does not say it,
    such as `date_time`'s `ARRAY OF SYSTEM.BYTE`.
  - Results (proposal 3): a condition value stays `SYSTEM.INT32`. The 15
    results whose type name is `longword_unsigned` or `word_unsigned`
    are CARDs, `LIB$LEN`'s a `CARD16`. The other 2 of SDL's 17 belong to
    `LIB$MATCH_COND` and `STR$FIND_FIRST_SUBSTRING`, which are left out.
- **`rtl/vax/vms`, regenerated.**
  - 1010 declarations changed in 26 of the 41 modules. The two
    misaligned fields' comments now name `SYSTEM.CARD32`.
  - `sdlload` made them on atla, and the guest's `tools/vax-sdl run`,
    with the rebuilt back end in `SYS$SHARE`, made the same 41 files.
- **`VmsArguments`** (proposal 4).
  - `length`, `bufferLength`, `status` and `count` are `CARD16`, and
    `dataType` and `class` are `CARD8`.
  - `SetItem`'s `returnLength` is `VAR SYSTEM.CARD16`.
  - The new `Card16` makes a length a `CARD16`. `Word` stays for the
    item code.
- **Fixtures** (proposal 6).
  - `VmsDefCalls` and `VmsCalls` hold lengths and the channel in `CARD16`
    variables, and their `Show` takes a `CARD16` length.
  - They print a CARD by `Out.Card` and a CARD status by
    `SYSTEM.VAL(LONGINT, ...)`, and set `FAB$L_FNA` by
    `SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(name))`.
  - `VaxVmsArguments`' `length` is a `CARD16`. Its expected MACRO-32 and
    `VmsArguments`' were regenerated, for review.
  - `vax-vmsdef` (0 layout errors, `STARLET.MLB`'s 3587 constants
    unchanged), `vax-vms-calls` and `vax-vms-arguments` pass on the
    guest, and print what they printed before.

## Part 2 finished: the other 58 modules (2026-10-15)

The user approved the first seven library modules on 2026-10-15, and the
other 58 of `STARLETSD.TLB` were generated the same day. `rtl/vax/vms`
now has 243 Oberon modules, from all 65 library modules, and 45,000
lines. The first 41 did not change.

- **What is left out**, each with a comment in its module. All of it is
  what the native library inventory left out already:
  - `CMA`, DECthreads: 64 routines whose results are SDL types 23 and
    24, which `sdldef.h` does not name, and 14 items that are not
    aggregates.
  - `MTH$`: the D floating, H floating and complex entries (results of
    types 6, 19, 20 and 21), 68 of them, and 20 with a `LIST` argument.
  - `DDTMDEF`, DECdtm: 4 octaword items that are not aggregates
    (`DDTM$X_TRANSACTION_ID`, `DDTM$X_UTC_DATE_TIME` and their `$S_`).
- **Two library modules with one SDL module's name** (decided by the
  user, 2026-10-15). `SMBMSG`'s SDL module is `$PSMMSGDEF`, as is
  `PSMMSG`'s, but its codes are `SMB$_`. `sdloberon.c`'s table
  `renamed`, keyed by the library module (the output file's name) and
  the SDL module, makes it `SMBMSGDEF`. `tools/vax-sdl run` refuses a
  run in which two library modules write one `.Mod`, rather than
  writing one over the other.
- **SDL's `ORIGIN`**: an aggregate's `typeinfo` is minus the offset of
  its origin field, and SDL's MACRO back end counts every offset
  constant from there (`DSCDEF`'s -12, `NSARECDEF`'s -4). The generator
  does so too, and says so in the record type's comment ("its offset
  constants count from its ORIGIN, n bytes in"), which
  `layout-check.awk` reads. The record's layout is unchanged.
- **`tools/vax-sdl`**: DCL reads a command of at most 255 characters,
  and the list of 58 modules in one symbol made a line of 492. Each
  module now has lines of its own in the procedure.
- **The library `VMSDEF`**, 243 modules, could not be linked on the
  guest: LINK holds every input file open, past `POC`'s FILLM and BYTLM.
  `-library`'s build procedure now links the shareable image from the
  object library with `/INCLUDE` (decided by the user, 2026-10-15;
  `vax-macro32-backend.md`, section 18.5).
- **`vax-vmsdef`**:
  - Every module compiles under `-O2` and `-OC`. `VMSDEF` builds on the
    guest, and `VmsDefLayout` checks 225 record types against SDL's
    offsets and sizes: 0 layout errors.
  - `STARLET.MLB` has a `$<M>` macro for 186 of the modules, listed in
    `mlb-modules`. The others are the routine modules, the message
    modules but `OPCMSG`, `OBJFMT`'s modules (`STARLET.MLB` has one
    `$OBJDEF` for them all), `PPL$DEF`, `SMGTRMPTR`, `LBRCTLTBL` and
    `CMA`. The `$LIB...DEF` macros take `..EQU` as their first
    parameter, not `$GBL`, so they are given `<==>`.
  - **17,559 names agree, and none differs in value.** 25 names are on
    one side only, recorded in `expected-mlb`, all `$S_` sizes or names
    that the macros were made with otherwise:
    - `LATDEF`'s four `$S_`, as before;
    - `$S_` of nested aggregates in `SMGDEF`, `CQUALDEF` and `DDTMDEF`
      that `STARLET.MLB` has, and of three bits aggregates in `CHPDEF`
      and `SMGDEF` that it has not, though it has `CHP$S_PROFILE_FLAGS`
      of the same shape. Those facilities' macros were evidently made by
      another run of SDL, so the generator follows the 41 modules' rule;
    - the facility codes `MOUN$_FACILITY` and `OPC$_FACILITY`, which
      the SDL trees call `MOUNT$_FACILITY` and `OPCOM$_FACILITY`;
    - four names that only the `..EQU` macros define: `CLI$CTRL_FIELDS`,
      `LIB$B_DCF_OPERAND`, `DT_DEFAULT_FIELDS` and `DT_PRINT_FIELDS`.

## Proposals, part 4: the hand-written modules (2026-10-15)

The native library inventory's proposal 4 (approved 2026-10-14) chose
three small modules over the generated interfaces: `Conditions`,
`LogicalNames` and `Symbols`. What the generated modules give them:
- `STARLET`: `SYS$GETMSG`, `SYS$TRNLNM`, `SYS$CRELNM` and `SYS$DELLNM`.
- `LIB_ROUTINES`: `LIB$GET_SYMBOL`, `LIB$SET_SYMBOL`,
  `LIB$DELETE_SYMBOL`, `LIB$SET_LOGICAL` and `LIB$DELETE_LOGICAL`, but
  not `LIB$SIGNAL` and `LIB$STOP`, which take a list.
- `STSDEF`, `PSLDEF`, `LNMDEF` and `LIBCLIDEF`: a condition's fields,
  the access modes, `$TRNLNM`'s items, the symbol tables.

Found in the manuals:
- **`LIB$SET_LOGICAL` asks DCL to define a supervisor-mode process
  logical name**, the same as `DEFINE`. Unlike `$CRELNM`, it needs no
  privilege, and the name outlives the image (`LIB$` manual, LIB-341). A
  name `$CRELNM` makes from user mode is deleted when the image exits.
  `LIB$DELETE_LOGICAL` is `DEASSIGN`.
- **`$CRELNM` maximizes the mode asked for with the caller's**, using
  the less privileged of the two, unless the caller has `SYSNAM`. So
  without it, a program in user mode that asks for an executive-mode
  name gets a user-mode one, with no error. A mode of 0 (kernel) means
  the caller's mode. The group table needs `GRPNAM` or `SYSPRV`, and
  the system table `SYSNAM` or `SYSPRV`; without them, `SS$_NOPRIV`
  (System Services Reference, SYS-82 to SYS-86).
- **`LIB$SET_LOGICAL` and the symbol routines need DCL.** Run as a
  subprocess or detached process, there is none, and they return
  `LIB$_NOCLI` (LIB-220, LIB-341).
- **`LIB$GET_SYMBOL` searches the local table, then the global one.** It
  uppercases the name, and returns a number as signed decimal text. A
  symbol's name has at most 255 characters (LIB-219).
- **A poc program establishes no condition handler**, apart from
  `POC_MATH`'s `LIB$SIG_TO_RET`. A signalled condition therefore reaches
  VMS's own handlers. A program is linked `/TRACEBACK`, LINK's default,
  so the handler prints the message and a traceback. It exits on a
  severe condition and otherwise continues (`LIB$` manual, LIB-366 to
  LIB-368).

### Proposals

**Approved by the user, 2026-10-15**, all seven.

1. **A library of their own, `VMSLIB`, in `rtl/vax/vmslib`**, which needs
   `VMSDEF` and `POCRTL`. They import the generated modules, so they
   cannot be in `POCRTL`, which `VMSDEF` needs. Nor can they be in
   `rtl/vax/vms`, which holds only what the generator writes. Step 6's
   `VMS` module would join them.

2. **A status is a `SYSTEM.INT32`**, as the generated declarations' is.
   Each procedure that calls VMS returns the condition value it got, not
   a `BOOLEAN`, so a program can test it with `Conditions.Success` and
   print it with `Conditions.Message`. An output string is truncated to
   its array, less one character, and ends with `0X`. The truncation is
   reported by the routine's own success status (`LIB$_STRTRU`,
   `SS$_BUFFEROVF`). An input string is passed up to its `0X`.

3. **`Conditions`**:
   ```oberon
   CONST Warning* = 0; Success* = 1; Error* = 2; Informational* = 3; Severe* = 4;
   PROCEDURE Succeeded*(status: SYSTEM.INT32): BOOLEAN;   (* bit 0 *)
   PROCEDURE Severity*(status: SYSTEM.INT32): INTEGER;    (* bits 0-2 *)
   PROCEDURE Facility*(status: SYSTEM.INT32): INTEGER;    (* bits 16-27 *)
   PROCEDURE MessageNumber*(status: SYSTEM.INT32): INTEGER; (* bits 3-15 *)
   PROCEDURE Message*(status: SYSTEM.INT32; VAR text: ARRAY OF CHAR);
   PROCEDURE Signal*(status: SYSTEM.INT32);
   PROCEDURE SignalWith*(status, argument: SYSTEM.INT32);
   PROCEDURE Stop*(status: SYSTEM.INT32);
   PROCEDURE StopWith*(status, argument: SYSTEM.INT32);
   ```
   - The test is `Succeeded`, since `Success` names the severity, as
     `STS$K_SUCCESS` does.
   - `Message` gives `$GETMSG`'s whole text, "%SYSTEM-F-ABORT, abort",
     which is what `$GETMSG` writes with every part of the message
     selected. Its `!` directives are left as written; `$FAO` is the
     supported tier's.
   - `Signal` and `Stop` call `LIB$SIGNAL` and `LIB$STOP` with the
     condition alone. `SignalWith` and `StopWith` pass one FAO
     argument, a longword: `(status, 1, argument)`. They are declared by
     hand in `Conditions`, with a fixed number of arguments each, two
     declarations to one routine. `Stop` never returns.

4. **`LogicalNames`**:
   ```oberon
   CONST User* = 3; Supervisor* = 2; Executive* = 1; Kernel* = 0;
     Process* = "LNM$PROCESS"; Job* = "LNM$JOB"; Group* = "LNM$GROUP";
     System* = "LNM$SYSTEM"; FileDevice* = "LNM$FILE_DEV";
   PROCEDURE Define*(table, name, value: ARRAY OF CHAR; mode: INTEGER): SYSTEM.INT32;
   PROCEDURE Deassign*(table, name: ARRAY OF CHAR; mode: INTEGER): SYSTEM.INT32;
   PROCEDURE Translate*(table, name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR): SYSTEM.INT32;
   PROCEDURE TranslateAt*(table, name: ARRAY OF CHAR; index: INTEGER;
                          VAR value: ARRAY OF CHAR; VAR last: INTEGER): SYSTEM.INT32;
   ```
   - **The mode chooses the routine.**
     - `Supervisor` defines and deassigns by `LIB$SET_LOGICAL` and
       `LIB$DELETE_LOGICAL`. The name outlives the program, as
       `DEFINE`'s does, and needs DCL.
     - Any other mode is `$CRELNM` and `$DELLNM`. A `User` name is gone
       when the program ends. `Executive` and `Kernel` take effect only
       with `SYSNAM`; without it, VMS makes a user-mode name, as
       `$CRELNM` says. `Kernel`, 0, is passed as 0, which `$CRELNM`
       takes as the caller's mode.
   - **One equivalence string** for `Define`; a list can come later.
   - **`Translate` is index 0.** `TranslateAt` gives the equivalence
     string at `index`, and in `last` the name's highest index, so a
     search list can be walked.
   - **Translation ignores case**, by `LNM$M_CASE_BLIND`, as
     `Platform.getEnv` and DCL do. Definition keeps the case written.

5. **`Symbols`**:
   ```oberon
   CONST Local* = 1; Global* = 2;   (* LIB$K_CLI_LOCAL_SYM, LIB$K_CLI_GLOBAL_SYM *)
   PROCEDURE Get*(name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR; VAR table: INTEGER): SYSTEM.INT32;
   PROCEDURE Set*(name, value: ARRAY OF CHAR; table: INTEGER): SYSTEM.INT32;
   PROCEDURE Delete*(name: ARRAY OF CHAR; table: INTEGER): SYSTEM.INT32;
   ```
   `Get` looks in the local table, then the global one, and sets `table`
   to where it found the symbol. A symbol is always a string here. A
   number comes back as its decimal text, and `Set` makes a string
   symbol, as `LIB$SET_SYMBOL` does.

6. **Fixture `vax-vmslib`**: `VMSLIB` built on the guest with `VMSDEF`
   and `POCRTL`, and programs linked against all three:
   - A program that tests `Conditions`' fields and messages on
     `SS$_NORMAL`, `SS$_ABORT`, `RMS$_FNF` and `LIB$_NOSUCHSYM`, and on
     an unknown code.
   - A program that defines, translates, redefines and deassigns names
     in each table it may use: user and supervisor modes, a search list
     made by DCL and walked by `TranslateAt`.
     It checks that an `Executive` name is made in user mode without
     `SYSNAM`, and that the group table is refused (`SS$_NOPRIV`). The
     guest procedure then shows with `SHOW LOGICAL` that the supervisor
     name outlived the program and the user name did not.
   - A program that sets, gets and deletes local and global symbols. The
     procedure checks the symbols that the program left.
   - Programs that call `Signal` (a warning, then an error: message,
     traceback, and the program goes on), `SignalWith` (an argument in
     the message) and `Stop` (a severe condition, which ends the
     program). Their status reaches DCL's `$STATUS`.

7. **Reference**: `rtl/vax/vmslib/README.md` lists the three
   interfaces, as `rtl/vax/README.md` does the runtime's. They are
   VAX-only, so the Reference Guide's runtime chapter, generated from
   `rtl/llvm`, does not change.

## Part 4 done: what was implemented (2026-10-15)

- **`rtl/vax/vmslib`**: `Conditions`, `LogicalNames` and `Symbols`, as
  proposed, and a `README.md`. They compile under `-O2` and `-OC`.
  - `Conditions` declares `LIB$SIGNAL` and `LIB$STOP` twice each, with
    one argument and with three. The VAX backend writes one `.EXTERNAL`
    for each linkage name.
  - A field of a status is taken by `DIV` and `MOD`, which floor, so a
    negative longword gives its bits.
- **Fixture `vax-vmslib`.** It builds `POCRTL`, a `VMSDEF` of only the
  six generated modules it imports (`LIBDEF`, `LIB_ROUTINES`, `LNMDEF`,
  `RMSDEF`, `SSDEF`, `STARLET`), and `VMSLIB`, on the guest, and runs
  five programs against them. Everything proposal 6 named came out as
  proposed:
  - **Conditions.** The parts and messages are as `F$MESSAGE` gives
    them. A code with no message gives "%NONAME-E-NOMSG, Message number
    0FFF8002", and a short array gets "%SYSTEM-F".
  - **Logical names.** Redefining gives `SS$_SUPERSEDE`, and translation
    ignores case. The search list's three names are walked. The group
    table gives `SS$_NOPRIV`. Afterwards DCL finds the supervisor name,
    and not the user name, the executive one (made in user mode) or the
    deassigned supervisor one.
  - **Symbols.** A local and a global symbol are set and got back. A
    number is got as "42" from the local table, a missing symbol gives
    `LIB$_NOSUCHSYM`, and a short array `LIB$_STRTRU`. DCL sees the two
    symbols set and not the global one deleted.
  - **Signals.** A warning, an error and an error with `!AS` are each
    printed, and the program goes on. `Stop` ends it with `SS$_ABORT`;
    DCL's `$STATUS` is `%X1000002C`, with the bit that says the message
    was printed. `StopWith` makes `LIB$_ACTIMAGE` severe,
    `%X101512BC`.
- **Found on the guest.** VMS's handler writes a signalled message and
  the traceback to `SYS$ERROR` only. Two `DEFINE/USER`s of one file, for
  `SYS$OUTPUT` and `SYS$ERROR`, open it twice, as two versions. So
  `guest-run.com` gives each stream a file of its own, and keeps only
  the `%` lines of `SYS$ERROR`'s, without the traceback.

## Proposals, part 5: argument lists through `LIB$CALLG` (2026-10-15)

**Approved by the user, 2026-10-15**, all five as written.

`LIB$SIGNAL` and `LIB$STOP` take a list: a condition, the count of its FAO
arguments and the arguments, then optionally another condition with its
own, and so on. poc has no variadic call. So the generator leaves both out,
along with `SYS$FAO`, `LIB$SYS_FAO`, `LIB$MATCH_COND`, `STR$CONCAT` and
`STR$FIND_FIRST_SUBSTRING` (part 2). `Conditions` declares each of the
first two twice, with one argument and with three. That gives `Signal`,
`SignalWith` (one FAO argument), `Stop` and `StopWith`, and nothing for a
message with two FAO arguments or for chained conditions.

`LIB$CALLG(argument_list, user_procedure)` calls a routine with an
argument list the caller builds, by `CALLG`, which is how a language
without variadic calls reaches such a routine. `LIB_ROUTINES` declares it,
with the list an `x-` `ARRAY OF SYSTEM.BYTE` and the routine a
`SYSTEM.ADDRESS`. `PLAN.md`'s "Ongoing language enhancements", item 3,
made on `main` and merged into `vax`, gives the address:
`SYSTEM.VAL(SYSTEM.ADDRESS, SignalAlone)`. These proposals come after that
merge and the item's VAX half.

1. **A guest test first**, in MACRO-32, with `tools/vax-do`. It calls
   `LIB$SIGNAL` directly by `CALLS`, and again through `LIB$CALLG`, each
   time with the same list, and compares:
   - the printed message and the traceback, with one condition and two
     FAO arguments, and with two chained conditions;
   - what a handler established in the caller sees: the signal array, its
     PC and PSL above all, and the mechanism array's depth;
   - Continue (both return to the caller) and an unwind to the
     establisher's caller;
   - `LIB$STOP` through `LIB$CALLG`: the message, and the image's exit
     status in DCL's `$STATUS`.

   What I expect, untried: `LIB$SIGNAL` takes the PC of its caller,
   which is now `LIB$CALLG`. The signal's PC and the top of the traceback
   then point into `LIBRTL`, one frame above the program's. The handler
   search starts at `LIB$CALLG`'s frame, which has no handler, and goes
   on to the program's, so handlers, Continue and unwinding work as for a
   direct call, at a depth one greater. The answers are written into a
   "Part 5, tried on the guest" section before any code depends on them.
   If the handler's view differs in more than the PC and the depth,
   proposal 2 is brought back to the user before it is built.

2. **`Conditions.SignalList` and `Conditions.StopList`:**

       PROCEDURE SignalList*(arguments-: ARRAY OF SYSTEM.INT32);
       PROCEDURE StopList*(arguments-: ARRAY OF SYSTEM.INT32);

   `arguments` is the list exactly as `LIB$SIGNAL` takes it, without
   the argument count: for example `{status, 2, count, name}` with a
   `!AS` argument as a descriptor's address (`VmsArguments`), or
   `{status1, 0, status2, 1, n}` for two conditions. The procedure copies
   it after a count into a local `ARRAY 256 OF SYSTEM.INT32` and calls
   `LIB$CALLG` with `SignalAlone`'s or `StopAlone`'s address.
   - `CALLG`'s count is a byte, so more than 255 arguments are refused:
     `Stop(LIB$_WRONUMARG)`, as a routine VMS calls with the wrong count
     refuses it.
   - `StopList` never returns. `SignalList` returns when a handler
     continues.
   - `Signal`, `SignalWith`, `Stop` and `StopWith` stay as they are,
     direct calls with no extra frame. The module comment says that a
     list's PC, as part 5's test found it, is `LIB$CALLG`'s.
   - `Conditions` imports `LIB_ROUTINES` for `LIB$CALLG`. `VMSLIB` needs
     `VMSDEF` already.

   Since `arguments` is an `x-` parameter, it takes an array variable or
   an array literal of a named type (Phase 14). The module's comment
   shows both: `TYPE Four = ARRAY 4 OF SYSTEM.INT32`, then
   `Conditions.SignalList(Four{status, 2, count, SYSTEM.ADR(name)})`, with `name` a
   `VmsArguments` descriptor.
   A wrong list is the caller's mistake, and is not checked, as from
   MACRO-32 or C.

3. **The other routines the generator leaves out stay left out.** Any of
   them can be reached the same way, `LIB$CALLG` with its address, and
   this file's part 2 note on them ("Left out, each with a comment")
   says so. Each gets an
   Oberon interface only when a program needs it, by the VAX module
   workflow. The generator is not changed.

4. **Fixture.** `vax-vmslib`'s `VmsLibSignal` gains:
   - a condition with two FAO arguments, one a number and one `!AS`;
   - two chained conditions;
   - a handler that prints the signal array it is given for a list, and
     continues;
   - and a program of its own, `VmsLibStopList`, that ends by `StopList`
     with one FAO argument, checked by DCL's `$STATUS`.

   The 256-argument refusal is shown by a third program,
   `VmsLibListTooLong`, which ends with `LIB$_WRONUMARG`.

5. **Documents.** A "Part 5 done" section here, `rtl/vax/vmslib/
   README.md`, and `PLAN.md` step 5's record.

## Part 5, tried on the guest (proposal 1, 2026-10-15)

A MACRO-32 program called `LIB$SIGNAL` both ways, with the same list each
time. Directly is `CALLG list, G^LIB$SIGNAL`. Through `LIB$CALLG` is
`LIB$CALLG(list, G^LIB$SIGNAL)`. Two programs did the same for `LIB$STOP`.
The lists were:
- `LIB$_ACTIMAGE` with one FAO argument, a `!AS` descriptor;
- that, with `SS$_IVLOGNAM` chained after it with none.

What came out:

- **The messages are the same.** "%LIB-E-ACTIMAGE, error activating image
  SOME_IMAGE", and for the chained list "-SYSTEM-F-IVLOGNAM, invalid
  logical name" on the next line. The program goes on after each, both
  ways.
- **The traceback has one more frame** through `LIB$CALLG`. It is a line
  with no module or routine name, at `LIB$CALLG`'s return address in
  `LIBRTL` (`%X00003EC4` here), above the routine that called it.
- **A handler sees the same signal array but for the PC.** The count
  (7 with a chained condition, 5 without) and the condition are the same,
  and so is the PSL (`%X03C00000`). Directly, the PC is the caller's return
  point. Through `LIB$CALLG`, it is `LIB$CALLG`'s, `%X00003EC4`. The
  mechanism array's depth is 0 directly and 1 through `LIB$CALLG`, since
  its frame is between.
- **Continue works both ways.** Control returns to the routine that
  signalled. The R0 it gets back is the mechanism array's, which
  `AA-LA66B` 2.12.1 says is "the same as at the time of the call to
  LIB$SIGNAL": the program's own directly (1 here), and `LIB$CALLG`'s
  through it (0). A `SignalList` that returns nothing does
  not see it.
- **An unwind works both ways.** A handler that calls `$UNWIND` with the
  mechanism array's depth (`DEPADR`) makes the signalling call return to
  the establisher, at the same place both ways, with the R0 it put in
  the mechanism array (`%X77`). The handler is not called again with
  `SS$_UNWIND` either way. The depth differs, so the same depth argument
  means the same thing both ways.
- **`LIB$STOP` is the same:** "%SYSTEM-F-ABORT, abort", the image ends,
  and DCL's `$STATUS` is `%X1000002C` both ways, with the traceback's extra
  frame through `LIB$CALLG`.
- **A hardware exception's code takes no FAO count.** The first lists
  tried were `SS$_ACCVIO`, made a warning, with "4" as its FAO count, and
  four arguments. VMS printed the 4 as ACCVIO's reason mask, and then the
  list's last argument and the signal array's PC and PSL as conditions of
  their own (`BADIMGHDR`, `OVRDSKQUOTA`, `NORMAL`). The 5.4 *Introduction
  to VMS System Routines* (`AA-LA66B`, 2.12.1) gives a hardware
  exception's signal array as its condition value, then "0 or several
  longwords" of "additional parameters", then the PC and PSL, with no
  count. It leaves the full format to `SYS$PUTMSG`'s description, in the
  System Services manual, which is not held yet. `SignalList`'s comment
  says that a list is exactly what `LIB$SIGNAL` takes, with no FAO count
  after a hardware exception's code.

So the handler's view differs in the PC, the depth, and the R0 given back
on a Continue. Proposal 1 asked for no more than the PC and the depth. The
R0 is invisible to `SignalList` and `StopList`, which return nothing, and
proposal 2 stands as written.

## Part 5 done: what was implemented (2026-10-15)

- **`Conditions.SignalList` and `StopList`**, as proposal 2 says. Each
  takes `arguments-: ARRAY OF SYSTEM.INT32`. A private `CallWithList`
  copies the list after its count into an `ARRAY 256` and calls
  `LIB_ROUTINES.LIB$CALLG` with `SYSTEM.VAL(SYSTEM.ADDRESS, SignalAlone)`
  or `StopAlone`. More than 255 longwords stop the program with
  `LIB$_WRONUMARG`. `Conditions` now imports `LIB_ROUTINES` and `LIBDEF`,
  which every `VMSDEF` that `VMSLIB` is built against already holds. The
  module's comment says how a list is written, that a hardware
  exception's code takes no FAO count, and what a handler sees
  differently (part 5, tried on the guest).
- **The VAX backend has no array literals yet** ("a record or array
  literal (Phase 16)"), so proposal 2's example of a literal list does not
  compile there. The comment and the fixtures fill a list element by
  element instead.
- **Fixture `vax-vmslib`**, against proposal 4. No VMS message with
  both a number and a `!AS` argument was found, so `VmsLibSignal`'s list
  is three chained conditions instead: `LIB$_ACTIMAGE` twice, each with
  its own `!AS`, then `SS$_IVLOGNAM` with none, 8 longwords in all.
  - Without a handler, VMS prints the three messages, the second and
    third as "-" lines, and the program goes on.
  - With a handler, the handler is given a count of 10: the 8, then the
    PC and PSL. It sees each condition and descriptor in order, at depth
    3 (`LIB$CALLG`, `CallWithList` and `SignalList` between), and the
    program goes on after it continues.
  - `VmsLibStopList` ends with `LIB$_ACTIMAGE` made severe, `$STATUS`
    `%X101512BC`, as `StopWith` does.
  - `VmsLibListTooLong` ends with `%LIB-F-WRONUMARG`, `%X1015835C`.
  - `guest-run.com` now keeps a `SYS$ERROR` line that starts "-" too, so
    the chained messages show. Each program run gets output files of its
    own: when `StopList` reused `StopWith`'s file names, `TYPE` showed
    both runs' lines.
  - `vax-asts` and `vax-conditions-handlers`, which build `VMSLIB` too,
    still pass.

## Proposals, part 6: RMS's indexed and relative files (2026-10-15)

The first of step 5's supported-tier groups
(`doc/research/vms-native-library-inventory.md`, proposal 4, "RMS"): what
`Files` cannot do, used synchronously. That means indexed and relative files,
keyed access, `$FIND`, `$UPDATE`, `$DELETE` and record locking. Asynchronous
RMS stays step 6's. The facts come from the *VMS Record Management Services
Manual* (`AA-LA83A`, 5.0), extracted to text for this. **Approved by the
user, 2026-10-15**, all six.

1. **No new module: a fixture that uses the generated declarations**, as the
   supported tier was defined. `STARLET` declares the services (`SYS$CREATE`,
   `SYS$CONNECT`, `SYS$PUT`, `SYS$GET`, `SYS$FIND`, `SYS$UPDATE`,
   `SYS$DELETE`, `SYS$CLOSE`). `FABDEF`, `RABDEF`, `XABDEF` and `XABKEYDEF`
   give the blocks as records, and `RMSDEF` gives the codes (`RMS$_DUP`,
   `RMS$_RNF`, `RMS$_RLK`, `RMS$_EOF`). A block is passed as `VAR ...: ARRAY
   OF SYSTEM.BYTE`, so a variable of its record type goes straight in. The
   fixture is also the worked example, and its comment shows the idiom. A
   VMSLIB module over keyed files (`IndexedFiles`, say) is left for when a
   program wants one; the fixture shows what it would wrap.

2. **What the program does in place of `$FAB`, `$RAB` and `$XABKEY`.** The
   macros fill in the block's identifier and length and their defaults.
   poc zeroes every variable, so the program sets those fields itself:
   - `BID`/`BLN` (`FAB$C_BID`, `FAB$C_BLN`, and so on);
   - every field the file needs: `ORG`, `RFM` (which the manual says must be
     set before `$CREATE`), `MRS`, `FAC`, `SHR`;
   - each address field (`FNA`, `XAB`, `FAB`, `UBF`, `RBF`, `KBF`), as
     `SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(x))`, since the generated fields
     are `CARD32`s.

   One difference matters. The manual says that a `$XABKEY` macro gives an
   alternate key duplicates and changeable values when `XAB$B_FLG` is
   defaulted, but a block not made by the macro gets the primary key's
   defaults: neither. A program sets `XAB$M_DUP` and `XAB$M_CHG` itself
   when it wants them. The fixture's comment says so.

3. **An XAB's common header has no names in its record.** `XABKEYDEF`, like
   every `XAB...DEF`, starts with `fill1` to `fill4`, since SDL defines
   `XAB$B_COD`, `XAB$B_BLN` and `XAB$L_NXT` once, in `$XABDEF`; the
   constants for their offsets are in `XABDEF`. I propose the program sets
   them by `SYSTEM.PUT` at those offsets, with no change to the generator:

       SYSTEM.PUT(SYSTEM.ADR(key) + XABDEF.XAB$B_COD, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEY));
       SYSTEM.PUT(SYSTEM.ADR(key) + XABDEF.XAB$B_BLN, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEYLEN));
       SYSTEM.PUT(SYSTEM.ADR(key) + XABDEF.XAB$L_NXT, SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(next)));

   The other way would be for `tools/sdloberon` to name a `FILL` that lies
   under `$XABDEF`'s fields, in each `XAB` it generates. That needs a special
   case for one SDL module, and a regeneration of `VMSDEF`, so I recommend
   against it unless the `PUT`s prove a nuisance.

4. **Fixture `vax-rms-indexed`, on the guest.** One program, `RmsIndexed`,
   prints each step's RMS status by name:
   - **Create** `PARTS.DAT`: indexed, fixed 40-byte records, two keys. The
     primary key (0) is an 8-character part number with no duplicates. The
     alternate key (1) is a 12-character location, with duplicates and
     changeable values.
   - **Put** six records out of order, then one whose part number is taken
     (`RMS$_DUP`).
   - **Read sequentially** by key 0 (part-number order), then by key 1
     (location order, the duplicates in the order they were put), each to
     `RMS$_EOF`.
   - **Keyed `$GET`s**: an exact match, a part number that is not there
     (`RMS$_RNF`), a generic match on its first characters (`RAB$B_KSZ`
     shorter than the key), and greater-or-equal (`RAB$M_KGE`).
   - **`$FIND` then `$UPDATE`**, changing a record's location, then a read
     by key 1 showing it moved. **`$FIND` then `$DELETE`**, then a read
     showing the record gone.
   - **Record locking**: a second `FAB` and `RAB` on the same file, opened
     for shared writing. The first stream holds a record it has read; the
     second's `$GET` of it is `RMS$_RLK`, since `RAB$M_WAT` is not set.
     After the first stream moves on, the second gets it.
   - **A relative file**, `SLOTS.DAT`, with records put by number (`RAC
     KEY`, `KBF` the record number), read by number, one number left empty
     (`RMS$_RNF`).

   The program imports only `VMSDEF`'s modules and `Out`, with no VMSLIB,
   and deletes its files at the end.

5. **Checked on the guest as written, not before.** Every call in proposal
   4 is in the 5.0 manual. What the manual does not settle is shown by the
   run and written into "Part 6 done":
   - whether a second stream in the same process sees `RMS$_RLK`, as two
     processes would;
   - the order of duplicates read by key 1.

   If either differs from the manual's reading, the fixture shows what the
   guest does, and the record says so.

6. **The documents.** "Part 6 done" here, the inventory's RMS entry marked
   done (with what was left out: `XABALL` areas, `XABPRO`, journaling,
   asynchronous RMS), and `PLAN.md` step 5.

## Part 6 done: what was implemented (2026-10-15)

Proposals 1-4 as written: no module, and fixture `vax-rms-indexed`
(`RmsIndexed.mod`), which imports only `STARLET`, `FABDEF`, `RABDEF`,
`XABDEF`, `XABKEYDEF`, `RMSDEF` and `Out`, and passes on the guest. The XAB
header is set by `SYSTEM.PUT` at `XABDEF`'s offsets, and the generator is
unchanged.

What the guest showed, the two points of proposal 5 first:
- **Two streams in one process lock each other out**, as two processes
  would. While the first stream holds P300 from a `$GET`, the second's
  `$GET` of it is `RMS$_RLK`; after the first reads another record, the
  second gets P300.
- **Duplicates of an alternate key come back in the order they were put**
  (`BIN-7`: P500, then Q100; `SHELF-A`: P100, then P310).
- **A `$PUT` whose alternate key is a duplicate gives `RMS$_OK_DUP`**, a
  success, not `RMS$_NORMAL`; a primary key already there gives
  `RMS$_DUP`.
- **A key buffer must hold the key as the record does.** RMS compares
  `RAB$B_KSZ` bytes of `RAB$L_KBF` with the record's, so a key `COPY`'d
  into a buffer, ending in `0X` and garbage, matches nothing (`RMS$_RNF`),
  and the `$UPDATE` and `$DELETE` after a failed `$FIND` give `RMS$_CUR`.
  The fixture pads its key with blanks, and its comment says why.
- A generic key (`RAB$B_KSZ` 2 for `P3`) finds the first record whose key
  starts so, and `RAB$M_KGE` the first at or after the key. A relative
  file's empty slot is `RMS$_RNF`.
- `FAB$M_DLT` in `FAB$L_FOP` before `$CLOSE` deletes the file; the
  procedure checks that none is left.

Left out, as proposal 6 says: `XABALL` areas, `XABPRO`, journaling, and
asynchronous RMS (step 6's rules would apply).

## Proposals, part 7: `SMG$` screen management (2026-10-16)

The second supported-tier group (`doc/research/vms-native-library-inventory.md`,
proposal 3, "`SMG$`"): what a full-screen program uses, which means
pasteboards, virtual displays, virtual keyboards, writing with renditions,
reading keys and strings, and menus. The facts come from the *VMS RTL Screen
Management (SMG$) Manual* (`AA-LA77A`, 5.0), extracted to text for this.
**Approved by the user, 2026-10-16**, all seven.

1. **No new module: fixtures that use the generated declarations**, as for
   RMS (part 6, proposal 1). `SMG_ROUTINES` declares the routines, `SMGDEF`
   gives the masks and codes (`SMG$M_BORDER`, `SMG$M_BOLD`, `SMG$K_VERTICAL`,
   `SMG$K_VTTERMTABLE`, `SMG$M_FORM_FEED`) and `SMGMSG` the statuses
   (`SMG$_EOF`, `SMG$_PASALREXI`, `SMG$_NOTRMSOUT`). A VMSLIB module over
   them (`Screens`, say) is left for when a program wants one.

   One cost comes with them. `SMG_ROUTINES` imports `AsynchronousTraps`,
   because of `SMG$`'s AST routines, so every program that calls `SMG$` gets
   the heap's AST bracket (section 22.5 of `vax-macro32-backend.md`: about 6
   microseconds a `NEW`). I propose to accept it. It is the price of the
   AST arguments being typed, and a full-screen program is not
   allocation-bound.

2. **A menu's choices need an array descriptor, and the generator gets
   them wrong.** `SMG$CREATE_MENU`'s `choices` is "static array of
   char_string ... by descriptor" (SMG-37): a `CLASS_A` descriptor of
   fixed-length strings. `tools/sdloberon` gives every character parameter
   passed by descriptor an open `ARRAY OF CHAR`, which poc passes as a
   `CLASS_S` descriptor of one string, so SMG would see a single choice.
   It is the only such parameter in the 243 modules.
   - **The generator:** a character parameter passed by descriptor whose
     SDL type name names an array (`STATICARRAYOFCHAR_STRING`) becomes "a
     descriptor built by hand", a `SYSTEM.ADDRESS` by value. That is the
     existing rule for a non-character descriptor, so the program passes
     `SYSTEM.ADR(descriptor)`. `VMSDEF` is regenerated: `SDLOBERON.EXE` is
     rebuilt on the guest, the user copies it to `SYS$SHARE`, and the guest's
     run must match the host's again. Only `SMG_ROUTINES` changes.
   - **`VmsArguments`:** `VmsArguments` gains an `ArrayDescriptor`, block 1 of
     the `CLASS_A` layout in `DSCDEF`'s comment. That is 16 bytes: length,
     type, class, pointer, scale, digits, flags, dimensions and `ARSIZE`,
     with no multipliers or bounds, since those blocks are optional.
     `DescribeArray(VAR descriptor: ArrayDescriptor; VAR elements: ARRAY OF
     ARRAY OF CHAR)` sets it up:
     - the length is `LEN(elements, 1)`;
     - the type is `T` and the class `A`;
     - the dimension count is 1, the flags 0;
     - `ARSIZE` is the whole array's bytes.

     It sits beside `StringDescriptor` and `Describe`. `DSCDEF5` could hold
     the same fields, but it carries `A0`, which belongs to block 2.
   - **Fixed-length strings:** the choices are fixed-length strings, so one
     shorter than its element is padded with blanks, not ended by `0X`. The
     manual says only that blank items are ignored; what SMG makes of a `0X`
     is for the guest to show (proposal 5). `DescribeArray` leaves the
     strings alone, and the fixture pads them itself, with a comment saying
     why, as `vax-rms-indexed` pads its keys.

3. **Fixture `vax-smg`, on the guest: the screen to a file.** The manual's
   way to capture a screen is a pasteboard on a file: "If input-device does
   not refer to a terminal, the file is opened using RMS", and `SMG$SNAPSHOT`
   "writes the current pasteboard buffer to the file" (SMG-367, section
   2.2.14). One program, `SmgFile`, prints each step's status by name with
   `Out` (on `SYS$OUTPUT`, which SMG does not use here) and does these
   steps:
   - **The pasteboard:** creates a pasteboard on `SCREEN.LIS` and prints the
     rows, columns and terminal type it gets back. That type is not
     `SMG$K_VTTERMTABLE`, so the manual says to snapshot. A second
     `SMG$CREATE_PASTEBOARD` on the same file is the manual's
     `SMG$_PASALREXI`, if a file counts as a device.
   - **The displays:**
     - A bordered display, its border labelled (`SMG$LABEL_BORDER`), with
       text put at given places in bold and in reverse (`SMG$PUT_CHARS`).
     - A second display, with a rectangle drawn in it (`SMG$DRAW_RECTANGLE`)
       and enough lines put to scroll it (`SMG$PUT_LINE`).
     - Both pasted so that one hides part of the other, then a snapshot.
     - The second moved and the first unpasted, then a snapshot with
       `SMG$M_FORM_FEED`, so that the two screens are told apart in the file.
   - **A menu:** a vertical menu (`SMG$CREATE_MENU`, through proposal 2)
     in a third display, and a snapshot.
   - **A keyboard on a file:** `KEYS.DAT`, written first by the program
     with `Files`.
     - `SMG$READ_STRING` reads its records one by one, to `SMG$_EOF`.
     - `SMG$READ_KEYSTROKE` reads a record, printing the code it returns.
     - `SMG$SELECT_FROM_MENU` reads from it, printing the choice or the
       status.
   - **The screens:** last, the program prints `SCREEN.LIS` through `Files`,
     so that the screens are in the fixture's output and its expected file.
     `guest-run.com` deletes both files.

   The program imports only `VMSDEF`'s modules, `VmsArguments`, `Files` and
   `Out`, with no VMSLIB.

4. **A terminal checked by hand, as `VT100` was (section 19.18 of
   `vax-macro32-backend.md`).** A second program, `SmgScreen`, in the same
   fixture directory but not run by `test.sh`, does the same on
   `SYS$OUTPUT` and `SYS$INPUT`:
   - the displays with their renditions;
   - a menu chosen with the arrow keys and Return;
   - a keystroke named by `SMG$KEYCODE_TO_NAME`;
   - a string read with a prompt;
   - and the screen restored at the end.

   It writes only through SMG, since `Out`'s buffered lines on the same
   terminal would come between SMG's. It is run through a telnet session by
   `expect`, with `VAX_ASSEMBLE_LOG` keeping the bytes, and by the user at a
   real VT100 emulator. "Part 7 done" records both.

5. **Checked on the guest as written, not before.** Every routine in
   proposals 3 and 4 is in the 5.0 manual. What it does not settle is shown
   by the run and written into "Part 7 done":
   - how big a pasteboard on a file is, and its terminal type;
   - what a border, a rectangle and a rendition become in a file;
   - whether a snapshot's lines keep their trailing blanks;
   - whether `SMG$PASALREXI` applies to a file;
   - what `SMG$READ_KEYSTROKE` and `SMG$SELECT_FROM_MENU` do with a keyboard
     on a file;
   - whether a `0X` in a choice shows.

   If `SMG$SELECT_FROM_MENU` needs a terminal, the fixture keeps the status
   it gets, and menus are checked only by hand (proposal 4).

6. **Left out**:
   - `SMG$`'s AST routines (unsolicited input, broadcast trapping, out of
     band): step 6's rules apply when a program wants them.
   - Viewports, subprocesses (`SMG$CREATE_SUBPROCESS`), key definition
     tables (`SMG$DEFINE_KEY`, `SMG$LOAD_KEY_DEFS`), the terminal table
     routines, and `SMG$PRINT_PASTEBOARD`, which queues the file to a
     printer.

   All are generated and callable. They are only not in a fixture.

7. **The documents:**
   - "Part 7 done" here;
   - proposal 2's rule in part 2's account of the generator;
   - `VmsArguments`' comment;
   - the inventory's `SMG$` entry marked done, with what was left out;
   - `PLAN.md` step 5.

## Part 7 done: what was implemented (2026-10-16)

Proposals 1 to 7 as written.
- **The generator** (proposal 2): `tools/sdloberon` gives a character
  parameter passed by descriptor whose type name contains `ARRAY` the
  hand-built descriptor's `SYSTEM.ADDRESS`. Run on atla by `sdlload` over a
  fresh dump of `SMG$ROUTINES`, it changes one line of the 243 modules,
  `SMG$CREATE_MENU`'s `choices`. `SDLOBERON.EXE` was rebuilt on the guest
  (`tools/vax-sdl build`). The guest's regeneration of all 65 SDL modules,
  which must match, waits for the user's copy to `SYS$SHARE`.
- **`VmsArguments`** has `classA`, `ArrayDescriptor` (16 bytes, the
  prototype block) and `DescribeArray`. `vax-vms-arguments`' two expected
  `.mar` files were regenerated: a new key, the new procedure, and moved
  line numbers.
- **Fixture `vax-smg`:** `SmgFile` imports only `SSDEF`, `SMGDEF`,
  `SMGMSG`, `SMG_ROUTINES`, `VmsArguments`, `Files` and `Out`, and passes
  on the guest. `SmgScreen` is compiled by `test.sh` and run by hand.

What the guest showed, proposal 5's points first:
- **A pasteboard on a file is 66 rows by 132 columns, of type
  `SMG$K_UNKNOWN` (0)**, a printer's page. A snapshot writes all 66 rows as
  variable-length records with carriage-return carriage control, each row's
  trailing blanks dropped. A blank row is a record of two blanks, which
  `SmgFile` prints as a count. `SMG$M_FORM_FEED` adds a record of its own,
  a form feed, before the rows.
- **A second `SMG$CREATE_PASTEBOARD` on the same file is not
  `SMG$_PASALREXI`**: it succeeds with another pasteboard and a new, empty
  version of the file (`SCREEN.LIS;2`), so `SmgFile` reads `;1`.
- **In a file, a border and a rectangle are `+`, `-` and `|`, and a
  rendition is dropped.** Text in bold and in reverse is plain. On a
  terminal they are the DEC special graphics characters (`lqqk`, `x`,
  `mqqj` between SO and SI), with `ESC [1m`, `ESC [7m` and `ESC [4m` for
  the renditions.
- **`SMG$MOVE_VIRTUAL_DISPLAY` and `SMG$UNPASTE_VIRTUAL_DISPLAY` return
  `SMG$_WILUSERMS`** on a file, a success. The next snapshot shows what
  they did. The others return `SS$_NORMAL`.
- **A keyboard on a file:**
  - `SMG$READ_STRING` returns a record a call, ended by 13 (Return), then
    `SMG$_EOF`.
  - `SMG$READ_KEYSTROKE` returns a record's first character (`x`, 120).
  - `SMG$SELECT_FROM_MENU` reads the next record's first character as a
    terminator (`B`, 66), leaves choice 1, and returns `SMG$_EOF`. **A menu
    is chosen only on a terminal**, so the fixture keeps that status, and
    menus were checked by hand.
- **The menu, built from blank-padded choices through
  `DescribeArray`**, shows the four choices in its bordered display, in the
  file and on the terminal. A choice padded with `0X` was not tried, since
  the fixture pads with blanks as the proposal says.

**Checked by hand** (2026-10-16), in a telnet session as POC driven by
expect, the terminal a VT100 with advanced video, its bytes logged.
`SmgScreen` drew the bordered display with its label, the bold, reverse
and underlined text, the `Colour` menu with "Red" in reverse, and the
prompt display. Two Down arrows (`ESC [B`) moved the reverse video to
"Green", then "Blue", and Return chose it. PF1 (`ESC OP`) at the
keystroke prompt and "hello smg" at the line prompt followed. Deleting the
pasteboard cleared the screen (`ESC [;H ESC [2J`) and reset the keypad
(`ESC >`), and the program printed:

```
choice 3, "Blue", terminator 13
key 256, PF1
typed "hello smg"
```

The user ran `SMGSCREEN.EXE` at a terminal the same day, choosing
"Violet", pressing Left as the keystroke, and typing the line by hand:

```
choice 4, "Violet", terminator 13
key 276, LEFT
typed "this is fun!"
```

## Proposals, part 8: `SOR$` sorting and merging (2026-10-16)

The third supported-tier group (`doc/research/vms-native-library-inventory.md`,
proposal 3, "`SOR$`"): sorting files by a key with `SOR$PASS_FILES` and
`SOR$SORT_MERGE`, and, since part 1's callbacks are proven (`vax-vms-calls`
passes Oberon procedures to `LIB$INSERT_TREE` and `LIB$TRAVERSE_TREE`), the
record interface with a comparison routine of the program's. The facts come
from the *VMS Utility Routines Manual* (`AA-LA67B`, 5.4), chapter 13,
extracted to text for this, and from the guest. **Approved by the user,
2026-10-16**, all eight.

1. **The constants that SORT defines are in no SDL module, so a small
   VMSLIB module holds them.** `SORDEF` has only the `SOR$_` status codes.
   The option flags (`SOR$M_`), the sort processes (`SOR$GK_`) and the
   statistic codes (`SOR$K_`) are universal symbols of `SORTSHR`, which
   "the application program should declare ... as external symbols"
   (SOR-1). A `CONST` cannot hold a linker's value, and a reference to an
   absolute symbol is the backend work the inventory left for later
   (proposal 4, "A program's own message codes"). So
   `rtl/vax/vmslib/SortMerge.Mod` declares them as constants, with the
   values a link against the guest's `SORTSHR` (V5-026, 8-JUL-1992) gives.
   Two differ from what the manual's order suggests:
   - `SOR$M_NODUPS` is 40H, not 10H.
   - `SOR$GK_INDEX` is 3 and `SOR$GK_ADDRESS` 4.

   The names are English, as VMSLIB's are (`CommandLanguage.Parsed`),
   each with its VMS name in a comment: `stable`, `ebcdic`,
   `multinational`, `noSignal`, `noDuplicates`; `recordSort`, `tagSort`,
   `indexSort`, `addressSort`; `recordsIn`, `recordsSorted`, `recordsOut`
   and the other thirteen statistics. The other way, VMS's own names
   (`SOR$M_STABLE`), would read like the manual; I recommend the English
   ones for VMSLIB's sake.

   `SortMerge` also has the key buffer's two orders (`ascending` 0,
   `descending` 1) and `AddKey(VAR keys: ARRAY OF SYSTEM.CARD16; dataType,
   order, offset, length: LONGINT)`, which puts one key's four words after
   those already there and counts it in `keys[0]` (SOR-25: the first word
   is the number of keys, then four words a key). Nothing else: the
   routines are `SOR_ROUTINES`'.

2. **The constants are checked against the linker on the guest.**
   `vax-sort`'s `guest-run.com` links a MACRO-32 module of `.LONG`
   references to the 25 symbols with `/MAP/FULL` and writes the map's
   lines for them. The program prints `SortMerge`'s constants the same
   way, and `test.sh` compares the two lists, so a `SORTSHR` with other
   values fails the fixture, as `vax-vmsdef` checks `VMSDEF` against
   `STARLET.MLB`.

3. **Statuses are compared without their severity.** "Some of the
   following condition values are used with different severities,
   depending on whether SORT/MERGE can recover. Thus, if you want to
   check for a specific status, you should use LIB$MATCH_COND" (SOR-29).
   The fixture compares a status with a code by facility and message
   number, bits 3 to 27, as `LIB$MATCH_COND` does. It prints one by its
   name when it knows it, and by its value otherwise.

4. **Fixture `vax-sort`, on the guest.** One program, `SortFiles`,
   imports `SOR_ROUTINES`, `SORDEF`, `SSDEF`, `DSCDEF`, `SortMerge`,
   `VmsArguments`, `Files` and `Out`. It prints each step's status and
   writes its input with `Files`, so the files are `Files`' own
   Stream_LF ones. Its records are 24 characters: a name (12), a
   department (6) and a salary (6 digits).
   - **The file interface:** `STAFF.DAT`, eight records, sorted to
     `STAFF.SRT` by department ascending (`DSC$K_DTYPE_T`), then salary
     descending (`DSC$K_DTYPE_NU`, a numeric string), with `stable`.
     `SOR$STAT` gives the records in and out and the longest record, and
     `STAFF.SRT` is printed through `Files`.
   - **No duplicates:** the same file sorted by department alone with
     `noDuplicates`, one record a department.
   - **A merge:** two files the program writes in name order, merged by
     `SOR$BEGIN_MERGE` (file interface, merge order 2) into one.
   - **The record interface with a comparison routine:**
     - Names are released one by one (`SOR$RELEASE_REC`), sorted with
       `lrl` and `user_compare`, and returned (`SOR$RETURN_REC`) to
       `SS$_ENDOFFILE`.
     - The routine is the manual's own example (SOR-2): names beginning
       "Mc" and "Mac" are placed together, and case is ignored.
     - It is passed as `SYSTEM.VAL(SYSTEM.ADDRESS, CompareNames)`. That
       sort uses a `context` longword, which starts at 0, so the routines'
       optional last argument is seen to work.
   - **Calls out of order:** `SOR$SORT_MERGE` with no sort begun gives
     `SOR$_SORT_ON` as a status, not a signal, since `noSignal` is the
     default (SOR-27).

5. **Two points about the generated declarations, which the fixture
   shows and its comments explain:**
   - **The comparison routine** is called by SORT with five arguments by
     reference: the two records, their two lengths, and the context
     (SOR-27). The Oberon procedure is `CompareNames(VAR a, b: Record;
     VAR lengthA, lengthB: SYSTEM.CARD16; VAR context: SYSTEM.CARD32):
     SYSTEM.INT32`, `Record` a fixed `ARRAY n OF CHAR`, and it returns
     -1, 0 or 1. Its `VAR` parameters must carry no hidden argument (not
     a record, which carries its tag, and not an open array), part 1's
     proposal 4. `user_compare` is a `SYSTEM.ADDRESS`, so poc cannot
     check that rule here; the program keeps it.
   - **`SOR$RELEASE_REC`'s record** is an `x-: ARRAY OF CHAR`, which
     poc describes up to its first `0X` (part 1, proposal 2). So a text
     record goes as its text, of any length up to the array's, but a
     record with a binary key in it would be cut at its first zero byte.
     The fixture's last step sorts four records with a signed longword
     key (`DSC$K_DTYPE_L`), one key 0 and one negative. They are released
     through a declaration of the program's own,
     `PROCEDURE ["VMS", "SOR$RELEASE_REC"] ReleaseBytes(descriptor:
     SYSTEM.ADDRESS; VAR context: SYSTEM.CARD32): SYSTEM.INT32`, given
     `SYSTEM.ADR` of a `VmsArguments.StringDescriptor` that covers the
     whole record. Records come back by `SOR$RETURN_REC`, whose `VAR`
     buffer is described whole, with the length returned.

6. **Checked on the guest as written, not before.** Every call in
   proposal 4 is in the 5.4 manual. What it does not settle is shown by
   the run and written into "Part 8 done":
   - whether SORT takes `Files`' Stream_LF files as input, and what
     record format its output has (by default, the first input's);
   - the statistics' values;
   - whether `noDuplicates` keeps the first record of each department.

   If SORT refuses Stream_LF, `guest-run.com` writes the input with
   DCL's `CREATE` instead, and the record says so.

7. **Left out**:
   - `SOR$SPEC_FILE` (specification files);
   - `SOR$DTYPE` and collating sequences other than ASCII, including
     `ebcdic` and `multinational`;
   - tag, address and index sorts;
   - `user_equal`;
   - the merge's record interface (`user_input`);
   - work-file placement.

   All are callable through `SOR_ROUTINES` and `SortMerge`'s constants.

8. **The documents:**
   - "Part 8 done" here;
   - the inventory's `SOR$` entry marked done;
   - `rtl/vax/vmslib/README.md`;
   - `PLAN.md` step 5.

   `vax-vmslib`'s list of modules gains `SortMerge`. `vax-asts` and
   `vax-conditions-handlers`, which build every module in
   `rtl/vax/vmslib`, build it too.

## Part 8 done: what was implemented (2026-10-16)

Proposals 1 to 8 as written:
- **`rtl/vax/vmslib/SortMerge.Mod`**: the 25 constants, `ascending` and
  `descending`, and `AddKey`. It imports only `SYSTEM`.
- **Fixture `vax-sort`:** `SortFiles` and `hand-sortsymbols.mar` (the
  `hand-` prefix keeps `testenv.sh` from deleting it). It passes on the
  guest, and the first thing it prints is "25 constants agree with
  SORTSHR, 0 differ".
- **`vax-vmslib`** compiles `SortMerge` under `-O2` and `-OC` and puts it
  in `VMSLIB`.

What the guest showed, proposal 6's points first:
- **SORT takes `Files`' Stream_LF files, and its output keeps their
  format.** `STAFF.SRT`, `DEPTS.SRT` and the merge's `NAMES.MRG` are all
  `STMLF`, as the manual's default (the first input's format) says, so
  `Files` reads them back as they are.
- **The statistics:** 8 records in and 8 out. The longest record in is 512
  for a Stream_LF input, which records no longest record of its own.
- **`noDuplicates` does not keep the first record of each key.** Of
  SALES's three, Garcia (first in) and Carter and Adams, it kept Adams;
  of ADMIN's, Baker; of ENGINE's, Diaz. Which record survives is SORT's
  business, and a program that cares uses `user_equal`.
- `stable` kept equal keys in their input order: Baker before Evans,
  Garcia before Adams.
- `SOR$SORT_MERGE` with no sort begun returns `SOR$_SORT_ON`.
- The comparison routine was called as proposal 5 says, and put
  "Mabry", "McAllister", "mcbride", "MacDonald", "macintosh", "Martin",
  "Mason" in that order. `SOR$END_SORT` left the context 0.
- **The binary keys** (-5, 0, 300 and 70000, whose bytes hold zeros) came
  back in order, each record its whole 8 bytes, through the program's
  own `SOR$RELEASE_REC` declaration.

Left out, as proposal 7 says. The inventory's `SOR$` entry is marked
done.

## Proposals, part 9: `STR$`'s decimal-string arithmetic (2026-10-16)

The fourth supported-tier group (`doc/research/vms-native-library-inventory.md`,
proposal 3, "`STR$`"): the one part of `STR$` that Oberon and `Strings`
lack, arithmetic on decimal numbers of any length: `STR$ADD`, `STR$MUL`,
`STR$DIVIDE` (the inventory's "`STR$DIV`"; `STR$DIVIDE` is its name),
`STR$RECIP` and `STR$ROUND`. The facts come from the *VMS RTL String
Manipulation (STR$) Manual* (`AA-LA75A`, 5.0), extracted to text for this.
**Approved by the user, 2026-10-16**, all eight.

How `STR$` gives a number: three arguments, a sign (0 positive, 1
negative), an exponent and a string of unsigned digits, so that the value
is the digits times 10 to the exponent with the sign applied. The manual's
example (STR-6): -1000 is sign 1, exponent 3, digits "1"; 0.0002 is sign 0,
exponent -4, digits "2"; their sum, -999.9998, comes back as sign 1,
exponent -4, digits "9999998". The generated declarations match the
manual: each part `x-` in and `VAR` out, the digits an `ARRAY OF CHAR` by
descriptor.

1. **A small VMSLIB module, `DecimalStrings`, and not the generated
   declarations alone**, unlike RMS's, SMG$'s and SOR$'s groups. Three
   things make the bare routines awkward in Oberon, and a module settles
   each once:
   - **Errors are signalled, not returned.** `STR$_DIVBY_ZER` and
     `LIB$_INVARG` are under "CONDITION VALUES SIGNALED" (STR-30). A poc
     program has no handler of its own, so a division by zero would print
     a message and a traceback and go on with an undefined result.
   - **The result has no length.** The digits come back in a fixed-length
     `CLASS_S` buffer with nothing to say how many there are.
   - **A number is three variables.** Reading one from text, or printing
     one, is the same code in every program.

   With the generated declarations alone, every program would need its
   own handler and its own conversions. I recommend the module.

2. **The representation and text.** `DecimalStrings.Decimal` is a record
   of `STR$`'s three parts, so each goes to the routine as it is:
   `sign: SYSTEM.CARD32`, `exponent: SYSTEM.INT32`, and `digits: ARRAY
   256 OF CHAR`, up to 255 digits ended by `0X`. Conversions:
   - `FromText(text, VAR d): BOOLEAN` reads an optional sign, digits and
     an optional point with digits after it (`-999.9998`, `+12`, `.5`),
     and returns `FALSE` for anything else.
   - `ToText(d, VAR text)` writes the plain form, with a point where the
     exponent puts one and zeros as needed (`-999.9998`, `2000`, `0.0002`).
   - `FromInteger(n: HUGEINT, VAR d)` makes one from an integer.

3. **Signals become statuses through `LIB$SIG_TO_RET`.** Each procedure of
   the module establishes `LIB$SIG_TO_RET` as its frame's handler before
   it calls `STR$`:
   ```
   LIB_ROUTINES.LIB$ESTABLISH(SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$SIG_TO_RET))
   ```
   This uses the address of an external procedure (`SYSTEM.VAL`,
   2026-10-15). A signal then makes the procedure return the condition as
   its status, with no message, which is what `POC_MATH` does for `Math`
   in MACRO-32 (`vax-macro32-backend.md`, section 19.16). So `Divide` by
   zero returns `STR$_DIVBY_ZER`.

   The caveat is `Math`'s too. Called at AST level, a condition signalled
   by the code the AST interrupted would also find this handler, so the
   module is not for AST routines. Its comment says so.

4. **The procedures:**
   - `Add`, `Subtract` (`STR$ADD` with the second sign flipped) and
     `Multiply`, each `(a, b: Decimal; VAR c: Decimal): SYSTEM.INT32`.
   - `Divide(a, b: Decimal; digits: LONGINT; round: BOOLEAN; VAR c)`:
     `STR$DIVIDE`'s total digits (digits to the right of the point) and
     its round-or-truncate indicator.
   - `Reciprocal(a, precision: Decimal; VAR c)` (`STR$RECIP`).
   - `Round(a: Decimal; places: LONGINT; truncate: BOOLEAN; VAR c)`
     (`STR$ROUND`).

   Each result's digits are trimmed to the digits proper and ended by
   `0X`, however `STR$` filled the buffer (proposal 6). The result is
   normalized, with no leading zeros, so that `ToText` and comparisons
   see one form. A result of more than 255 digits returns `STR$_TRU`,
   the routine's own truncation warning, as the manual says. An operand
   is a value parameter and a result a `VAR` one, as in `Strings`. The
   operands are copies, so `Add(x, y, x)` works.

5. **Fixture `vax-decimal-strings`, on the guest.** One program,
   `DecimalUse`, imports `DecimalStrings`, `STR_ROUTINES`, `STRDEF`, `Out`
   and the codes it prints. It prints each step's status by name:
   - **The manual's example,** -1000 + 0.0002 = -999.9998, through the
     module and once through `STR$ADD` itself, printing the raw 40-character
     buffer between bars, to show how `STR$` fills it.
   - **Beyond `HUGEINT`:** 123456789012345678901234567890 ×
     987654321098765432109876543210, exactly, and a subtraction that
     crosses zero.
   - **`Divide`:** 1 / 3 and 2 / 3 to 20 digits, truncated and rounded,
     then a division by zero, `STR$_DIVBY_ZER` as a status with no
     traceback.
   - **`Reciprocal`** of 7 to a precision of 10 to the -15th.
   - **`Round`** of 3.14159265 and of -2.5 to a few places, rounded and
     truncated.
   - **`FromText`** refusing `1.2.3` and `12a`; `ToText` of large and
     small exponents.
   - **A buffer too short,** through `STR$MUL` itself with a 5-character
     result, which returns `STR$_TRU` and shows what is kept.

6. **Checked on the guest as written, not before.** What the manual does
   not settle is shown by the run and written into "Part 9 done":
   - **how `STR$` fills a fixed-length result:** left-justified and
     blank-padded, as `STR$`'s string copies are (STR manual 2.2), or
     right-justified with zeros;
   - whether a result carries trailing zeros or leading zeros, and which
     exponent it chooses;
   - **`STR$ROUND`'s `places`:** "maximum number of decimal digits"
     (STR-80), digits after the point or significant digits ("rounds ... to
     a specified number of significant digits", STR-81);
   - **`STR$RECIP`'s precision:** what the second operand's value means;
   - **`STR$_DIVBY_ZER`'s severity,** and whether `LIB$SIG_TO_RET`'s unwind
     gives it back unchanged.

   The module's comment states the answers, and its trimming does what the
   guest shows.

7. **Left out:**
   - The rest of `STR$` (copies, comparisons, searches, translations,
     dynamic strings), which `Strings` and Oberon's own strings cover;
   - `STR$CONCAT` and `STR$FIND_FIRST_SUBSTRING`, whose list arguments
     the generator leaves out.

   They are callable through `STR_ROUTINES`, but not wrapped.

8. **The documents:**
   - "Part 9 done" here;
   - the inventory's `STR$` entry marked done, with `STR$DIVIDE`'s name
     corrected;
   - `rtl/vax/vmslib/README.md`;
   - `PLAN.md` step 5.

   `vax-vmslib`'s list gains `DecimalStrings`, and `vax-asts` and
   `vax-conditions-handlers` build it with every other VMSLIB module.

## Part 9 done: what was implemented (2026-10-16)

Proposals 1 to 8 as written:
- **`rtl/vax/vmslib/DecimalStrings.Mod`**: `Decimal`, the six arithmetic
  procedures, each establishing `LIB$SIG_TO_RET`, and `FromText`,
  `FromInteger` and `ToText`. It imports `STR_ROUTINES` and
  `LIB_ROUTINES`, so `vax-vmslib`, `vax-asts` and
  `vax-conditions-handlers`, which build every VMSLIB module, now put
  `STR_ROUTINES` in VMSDEF.
- **Fixture `vax-decimal-strings`:** `DecimalUse`, which passes on the
  guest. Every result is exact: the 60-digit product, 1 / 3 and 2 / 3 to
  20 digits, `MIN(HUGEINT)` - 1.
- **`vax-vmslib`** compiles `DecimalStrings` under `-O2` and `-OC` and puts
  it in `VMSLIB`.

What the guest showed, proposal 6's points in order:
- **A fixed-length result is right-justified and filled with zeros**, not
  blanks: `STR$ADD`'s 40-character buffer for the manual's example came
  back as `|000...0009999998|`, sign 1, exponent -4, as the manual says.
- **Trailing zeros go into the exponent.** The product
  123456789012345678901234567890 × 987654321098765432109876543210 came back
  as 58 digits with exponent 2, and 123456.789 rounded to 2 places as
  digits "12", exponent 4. Leading zeros are the fill only, and
  `DecimalStrings` drops them.
- **`STR$ROUND`'s `places` counts significant digits**: 123456.789 to 2 is
  120000, 3.14159265 to 4 is 3.142 (3.141 truncated), and -2.5 to 1 is -3,
  a half rounded away from zero.
- **`STR$RECIP`'s precision** is the place of the last digit wanted, and
  the result has one digit past it, truncated: 1 / 7 to a precision of
  0.000000000000001 is 0.1428571428571428 (exponent -16).
- **`STR$_DIVBY_ZER` is severe** (%X0024804C), and `LIB$SIG_TO_RET` returns
  it unchanged, with no message. After it, `c` is not a value: `Divide`
  left sign 1 and exponent -5 from what `STR$DIVIDE` had written, with
  digits "0".

And one point the proposals did not ask:
- **`STR$_TRU` gives a wrong result, not a shortened one.** 12345 × 6789
  into a 5-character buffer returned `STR$_TRU` with digits `83810` and
  exponent 0: the product's first five digits, 83810205's, without the
  exponent that would make them its approximation. So after `STR$_TRU` a
  result is not a value, as after an error, and `DecimalStrings`' comment
  says so. With its 255-character buffer, a `DecimalStrings` result is cut
  only past 255 digits.

`FromText` accepts "+12", ".5" and "-0.000" (keeping digits "0000", so
`ToText` prints "0.000"), and refuses "1.2.3", "12a" and "-". `ToText`
prints exponent 5 on "42" as 4200000, and exponent -8 as -0.00000042.

Left out, as proposal 7 says. The inventory's `STR$` entry is marked
done, with `STR$DIVIDE`'s name corrected.

## Proposals, part 10: the rest of `LIB$`'s supported tier (2026-10-16)

The fifth and last supported-tier group (`doc/research/vms-native-library-inventory.md`,
proposal 3, "`LIB$`"). The facts come from the *VMS RTL Library (LIB$)
Manual* (`AA-LA76A`, 5.0), extracted to text for this. **Approved by
the user, 2026-10-16**, all eight, with process control a part of its own.

The inventory names six kinds of routine. Three are done already:
- **Symbols and logical names:** VMSLIB's `Symbols` and `LogicalNames`
  (part 4).
- **Event flags:** VMSLIB's `EventFlags` (step 6).
- **The condition routines:** VMSLIB's `Conditions` and step 6.

This part covers the other three: information, dates and times, and
balanced trees, with the interlocked queue and bit routines step 6 left as
bare declarations. The generated declarations in `LIB_ROUTINES` match the
manual for all of them, so nothing in `sdloberon.c` changes.

1. **Information: the generated declarations, no module.** `LIB$GETJPI`,
   `LIB$GETSYI` and `LIB$GETDVI` already take one item each with no item
   list, which is the whole point of them (LIB-187: "Instead of a list of
   item descriptors, which may be difficult to construct in high-level
   languages"). Every optional argument is omitted by `NIL`.
   - A numeric item comes back in `resultant_value`, an `ARRAY OF
     SYSTEM.BYTE` that takes a `SYSTEM.INT32` or a `HUGEINT`, as Table
     LIB-5 says the item needs.
   - A string comes back in `resultant_string`, a `CLASS_S` buffer, with
     its length in `resultant_length`. The program ends it by `0X`, as it
     does for `SMG$`'s and `RMS`'s strings.
   - For a numeric item, `LIB$GETJPI` also writes a string form: a UIC as
     `[g,m]`, a PID as 8 hex digits, a privilege mask as names, a state
     as `LEF`, `COM` ... A module would add nothing over that.

   The item codes come from `JPIDEF`, `SYIDEF` and `DVIDEF`, which are
   generated already.

2. **Dates and times: a small VMSLIB module, `DateTimes`.** A VMS time is
   a quadword of 100-nanosecond units: an absolute time counts from 17
   November 1858 and is positive, and a delta time is negative. In poc
   that is a `HUGEINT`. The generated declarations take one as it is
   (`x-` by reference), so the module is mostly about text, which always
   needs its length and a `0X`:
   - `Time* = HUGEINT`, with `ticksPerSecond* = 10000000`.
   - `Now(): Time` (`$GETTIM`).
   - `FromText(text, VAR t): SYSTEM.INT32` (`$BINTIM`): an absolute time
     `16-OCT-2026 12:34:56.78` or a delta `1 02:00:00`, with `$BINTIM`'s
     defaults for the fields left out.
   - `ToText(t, VAR text)` (`$ASCTIM`): the standard form, ended by `0X`.
   - `Add(a, b, VAR c)` and `Subtract(a, b, VAR c)`, each returning
     `SYSTEM.INT32` (`LIB$ADD_TIMES`, `LIB$SUB_TIMES`). These and not
     Oberon's `+` and `-`, because they check what the manual requires:
     two absolute times cannot be added (`LIB$_ONEDELTIM`), and a delta
     must be under 10,000 days (`LIB$_IVTIME`).
   - `Delta(units, n: SYSTEM.INT32; VAR t): SYSTEM.INT32`
     (`LIB$CVT_TO_INTERNAL_TIME`): `n` weeks, days, hours, minutes or
     seconds as a delta time, `units` one of `LIBDTDEF`'s
     `LIB$K_DELTA_*`.
   - `Part(part, t; VAR value: SYSTEM.INT32): SYSTEM.INT32`
     (`LIB$CVT_FROM_INTERNAL_TIME`): one of `LIBDTDEF`'s `LIB$K_*`
     (day of year, hour of day, Julian date ...).
   - `DayOfWeek(t): INTEGER` (`LIB$DAY_OF_WEEK`): 1 for Monday to 7 for
     Sunday.
   - `Format(t, VAR context: SYSTEM.CARD32, VAR text): SYSTEM.INT32`
     (`LIB$FORMAT_DATE_TIME`), with the context cell the manual
     recommends (LIB-170: without one, two threads of execution, such as
     an AST and the main line, may break it). The context starts at 0,
     and the program frees it with `LIB$FREE_DATE_TIME_CONTEXT`. A
     language or format chosen in the program goes through the generated
     `LIB$INIT_DATE_TIME_CONTEXT`.

   These `LIB$` routines return their errors and do not signal them, so
   the module needs no handler, unlike `DecimalStrings`, and AST routines
   can use it. For portable programs, `Oberon.Time` and
   `Platform.GetClock` stay as they are.

   Without the module, every program would need its own `$ASCTIM`
   buffer, length and `0X`, and its own delta from units. I recommend
   it.

3. **Balanced trees: a VMSLIB module, `BalancedTrees`, of records the
   collector sees.** Part 1's `vax-vms-calls` already showed the callbacks
   working, with nodes in a static array. That is the problem: nodes from
   `NEW` would be lost to the collector, and `LIB$GET_VM` memory cannot
   hold Oberon pointers. But a `LIB$` node's 10-byte header is two
   absolute addresses and a word (LIB-240), which is exactly what an
   Oberon record of two pointers and a `SYSTEM.INT16` is, since an
   object's address is that of its first field. So:
   ```
   Node* = POINTER TO NodeDesc;
   NodeDesc* = RECORD left, right: Node; balance: SYSTEM.INT16 END;
   Tree* = RECORD root: Node END;
   Compare* = PROCEDURE (a, b: Node): LONGINT;
   Action* = PROCEDURE (node: Node): BOOLEAN;
   ```
   - A program extends `NodeDesc` with its own key and data, and the
     collector traces `left` and `right` as it traces any pointer field.
     `LIB$` writes them, so they are not exported.
   - `Insert(VAR tree: Tree; node: Node; compare: Compare; duplicates:
     BOOLEAN; VAR found: Node): SYSTEM.INT32`. The program makes and
     fills the node before the call, and the allocation routine
     `LIB$INSERT_TREE` requires just hands it back. The status is
     `LIB$_NORMAL`, or `LIB$_KEYALRINS` with `found` the node already
     there when `duplicates` is `FALSE`; `node` is then left out, and
     the collector frees it if nothing else holds it.
   - `Lookup(VAR tree: Tree; key: Node; compare: Compare): Node`: the
     node `compare` finds equal to `key`, or `NIL`. `key` is a node of
     the program's type with only its key filled.
   - `Traverse(VAR tree: Tree; action: Action): SYSTEM.INT32`: `action`
     for each node, in key order; `FALSE` stops the walk.

   **How the program's procedures reach the callbacks.** `LIB$`
   passes its `symbol` argument through to the comparison and
   allocation routines unchanged. `LIB$LOOKUP_TREE` has no `user-data`.
   So the module passes as `symbol` the address of a record in its own
   frame, holding the node and the program's procedure. Its three
   callbacks are module procedures of the shape part 1 allows: value
   parameters of 4 bytes, a `Node` among them. They read that record
   and call the program's procedure. The module declares its own
   `["VMS", "LIB$INSERT_TREE"]` and the other two, so that `treehead`
   is the `Node` field itself and not a `SYSTEM.ADDRESS`, as `vax-sort`
   declared its own `SOR$RELEASE_REC`. It keeps no state of its own
   between calls.

   I recommend this over leaving trees to the generated declarations,
   which leaves each program to manage its node memory by hand.

4. **Interlocked queues and bits: the generated declarations, no
   module, and the rules written down.** Step 6 chose to share data with
   an AST by disabling ASTs, and left `LIB$INSQHI` and the rest "for
   whoever wants them" (`vax-macro32-backend.md`, section 22.3,
   proposal 4). That holds. What this part adds is a fixture and the rules
   a program must follow, in the `vax-macro32-backend.md` section and the
   VMSLIB README:
   - **A header and every entry must be quadword aligned** (LIB-248).
     poc aligns a global or a local to at most a longword
     (`MemoryLayout.Align`), but `NEW` gives quadword-aligned memory: an
     object's data starts 8 bytes into a 16-byte granule. So a header
     and its entries are made by `NEW`, and a header starts at 0, its
     empty state.
   - **An entry linked only through a queue is invisible to the
     collector**, since the links are displacements. A program keeps an
     ordinary pointer to each entry while it is queued.
   - `LIB$REMQHI` gives the entry's address, and `SYSTEM.VAL` makes it
     the program's pointer type again.
   - `LIB$BBSSI` and `LIB$BBCCI` return the bit's old state, and
     `LIB$ADAWI` adds to a word that is word aligned.

5. **Fixtures, on the guest:**
   - **`vax-lib-information`:** prints only what does not change from
     run to run: `JPI$_USERNAME` (`POC`), `JPI$_MODE`, `SYI$_VERSION`
     and `SYI$_NODENAME`, and `DVI$_DEVCLASS` of a disk. Then it
     checks that `JPI$_PID`'s value and its 8-digit string agree. It
     also shows `SS$_BADPARAM` for a bad item code, `LIB$_INVARG` for a
     string-only item with no `resultant_string`, and `LIB$_STRTRU`
     for a buffer too short.
   - **`vax-date-times`:**
     - `16-OCT-2026 12:34:56.78` read and printed back;
     - plus a delta of 1 day 2 hours, and the delta between two times;
     - two absolute times added, `LIB$_ONEDELTIM`;
     - the day of the week (5, a Friday), the day of the year (289), and
       the Julian date;
     - `Format` of the same time, with a context and with the default
       format;
     - a delta of 90 minutes from `Delta`.
   - **`vax-balanced-trees`:** a program's records with a word as the
     key, inserted out of order with a repeat:
     - once with duplicates refused (`LIB$_KEYALRINS`, `found` the first
       node) and once allowed;
     - a `GarbageCollectedHeap.Collect` between the inserts and the walk,
       to show the nodes survive it;
     - the walk in order, a walk stopped early, and a lookup that finds
       and one that does not.
   - **`vax-interlocked`:**
     - entries made by `NEW`, inserted at the head and the tail and
       removed from both, with `LIB$_ONEENTQUE` and `LIB$_QUEWASEMP`;
     - each entry's address printed modulo 8, to show the alignment;
     - `LIB$BBSSI` and `LIB$BBCCI` on a set's bits;
     - `LIB$ADAWI`, with the sign it reports.
   - `vax-vmslib` compiles `DateTimes` and `BalancedTrees` under `-O2`
     and `-OC` and puts them in VMSLIB, and `vax-asts` and
     `vax-conditions-handlers` build them with every other VMSLIB module.

6. **Checked on the guest as written, not before.** What the manual does
   not settle is shown by the run and written into "Part 10 done":
   - **`LIB$FORMAT_DATE_TIME`'s formats.** It reads executive-mode
     logical names that `SYS$STARTUP:LIB$DT_STARTUP.COM` defines (LIB-171).
     Has the guest run it, and what does the default format give
     without it?
   - **`LIB$INSERT_TREE` with a duplicate refused:** is the allocation
     routine called at all? (LIB-239: "LIB$INSERT_TREE always calls the
     allocate routine.")
   - **`LIB$TRAVERSE_TREE`:** is the order in key order, as the manual's
     example implies, and does an action's failure status stop the walk?
     If not, `Traverse` stops by itself, and its comment says how.
   - **`LIB$GETJPI`:** whether a `JPI$_MODE` or `SYI$_VERSION` string is
     blank-padded; the manual removes trailing blanks only from
     blank-padded items such as `JPI$_USERNAME`.
   - **`LIB$CVT_FROM_INTERNAL_TIME`** of a delta time, for the units
     that allow one.

   The modules' comments state the answers.

7. **Left out:**
   - process control (`LIB$SPAWN`, `LIB$DO_COMMAND`, `LIB$RUN_PROGRAM`,
     `LIB$ATTACH`);
   - `LIB$FIND_FILE` and `LIB$RENAME_FILE`/`LIB$DELETE_FILE`, which
     `Files` and `Directories` cover in part;
   - `LIB$FIND_IMAGE_SYMBOL`, dynamic loading, which would need the
     image's symbols to match poc's names;
   - virtual memory zones, timers (`LIB$INIT_TIMER`, `LIB$SHOW_TIMER`);
   - conversions (`LIB$CVT_DTB` ...), the character instructions
     (`LIB$LOCC`, `LIB$MATCHC`, `LIB$SCANC` ...), `LIB$CRC`,
     `LIB$EDIV` and `LIB$EMUL`;
   - `LIB$TPARSE` and `LIB$CRF_*`, as the inventory says.

   They are callable through `LIB_ROUTINES`, but not checked. Process
   control is a part of its own (the user, 2026-10-16): `LIB$SPAWN` of a
   DCL command with output to a file, and its completion, which can be an
   AST.

   **Amended (the user, 2026-10-16):** `LIB$GETQUI`, first left out here,
   joins proposal 1. It is the same kind of routine as the other three,
   one item without an item list, with a function code (`QUI$_DISPLAY_QUEUE`
   ...) and an optional search name, number and flags. `vax-lib-information`
   asks about the guest's one queue, `SYS$BATCH`.

8. **The documents:**
   - "Part 10 done" in `vms-sdl-interfaces.md`;
   - the inventory's `LIB$` entry marked done, with what was already done
     by parts 4 and step 6 said so;
   - `vax-macro32-backend.md`, section 22, gets the queue rules;
   - `rtl/vax/vmslib/README.md` for `DateTimes` and `BalancedTrees`;
   - `PLAN.md` step 5, "Part 11". With this, step 5's supported tier is
     done, and step 8's exit gate is next.

## Part 10 done: what was implemented (2026-10-16)

Proposals 1 to 8 as written, with one change to `BalancedTrees` that the
guest asked for (below):
- **`rtl/vax/vmslib/DateTimes.Mod`** and **`rtl/vax/vmslib/BalancedTrees.Mod`**,
  each compiled under `-O2` and `-OC` by `vax-vmslib` and put in
  VMSLIB. `BalancedTrees` declares its own `LIB$INSERT_TREE`,
  `LIB$LOOKUP_TREE` and `LIB$TRAVERSE_TREE`, with the tree head a `Node`
  and the callbacks typed.
- **Four fixtures on the guest:**
  - `vax-lib-information` (`InfoUse`);
  - `vax-date-times` (`DateUse`);
  - `vax-balanced-trees` (`TreeUse`), which also calls `LIB$INSERT_TREE`
    and `LIB$TRAVERSE_TREE` through declarations of its own, to answer
    proposal 6's questions;
  - `vax-interlocked` (`QueueUse`).

  All four pass.
- `vax-asts` and `vax-conditions-handlers` build both with every other
  VMSLIB module; the generated modules they already build hold all that
  the two import.

What the guest showed, proposal 6's points first:
- **`LIB$FORMAT_DATE_TIME`'s default format is VMS's standard form,**
  `16-OCT-2026 12:34:56.78`, with `SS$_NORMAL`: the guest defines no
  `LIB$DT_FORMAT`. A format set by `LIB$INIT_DATE_TIME_CONTEXT` works
  without the startup's logical names: `|!Y4-!MN0-!D0|!H04:!M0:!S0|`
  gave `2026-10-16 12:34:56`.
- **`LIB$INSERT_TREE` does not call the allocate routine for a duplicate
  it refuses**, whatever "always" means on LIB-239: four inserts and a
  refused repeat made four calls.
- **`LIB$TRAVERSE_TREE` walks in key order, and an action's failure stops
  it** and becomes its status: with five nodes and `SS$_ABORT` from the
  third action, three actions ran and the walk returned `SS$_ABORT`.
  So `BalancedTrees.Traverse`'s action routine returns a failure when
  the program's `Action` returns `FALSE`, and `Traverse` returns
  `LIB$_NORMAL` for a walk stopped so. As first written, it went on
  calling `LIB$`'s action and skipped the program's.
- **`LIB$GETJPI` pads `JPI$_USERNAME` with blanks** (`POC` and nine blanks,
  length 12), though LIB-187 says it removes them. `JPI$_MODE` is
  `INTERACTIVE` and `SYI$_VERSION` `V5.5-2H4`, unpadded. `SYI$_NODENAME`
  is empty on the guest, which has no DECnet. A numeric item's string is
  its decimal value (`DVI$_DEVCLASS` of a disk: `1`), and `JPI$_PID`'s
  string is the value's 8 hex digits.
- **`LIB$GETQUI`** (the amendment) answers as DCL's `F$GETQUI` does on the
  guest, whose one queue is `SYS$BATCH`:
  - by name, its `QUI$_QUEUE_NAME`, its `QUI$_JOB_LIMIT` (3) and its
    `QUI$_QUEUE_FLAGS`, with `QUI$M_QUEUE_BATCH` set;
  - `QUI$_TRANSLATE_QUEUE` of `sys$batch`, `SYS$BATCH`;
  - a wildcard `*`, called three times: `SYS$BATCH`, then
    `JBC$_NOMOREQUE` with an empty string, then `SYS$BATCH` again, as
    the manual's "retains context" means;
  - `QUI$M_SEARCH_FREEZE_CONTEXT` keeps the wildcard on its queue, so two
    items come from the same queue, and `QUI$_CANCEL_OPERATION` ends it;
  - a queue that does not exist, `JBC$_NOSUCHQUE`.

  Its `resultant_length` is a signed word, unlike the other three's.
- **`LIB$CVT_FROM_INTERNAL_TIME`** of a delta gives its `LIB$K_DELTA_`
  units (90 for 90 minutes) and refuses the others with
  `LIB$_ABSTIMREQ`. A `LIB$K_DELTA_` part of an absolute time is
  `LIB$_DELTIMREQ`.

And what the proposals did not ask:
- `LIB$K_HOUR_OF_DAY` counts from 0 (12 at 12:34), though LIBDTDEF's
  comment says 1-24. `LIB$K_JULIAN_DATE` is the day's number from 17
  November 1858 (61329 for 16 October 2026), not the astronomers' Julian
  day.
- `$BINTIM` takes a field left out of an absolute time from the current
  time, so `16-OCT-2026` is that day at this moment's time of day. The
  fixture does not print it.
- `LIB$ADD_TIMES` of two absolute times is `LIB$_ONEDELTIM`, and a delta
  of 20,000 days is `LIB$_IVTIME` from `LIB$CVT_TO_INTERNAL_TIME`, as
  the manual's 10,000-day limit says.
- The queues: `NEW` gave a quadword-aligned header and entries; an empty
  queue gives back the header's own address with `LIB$_QUEWASEMP`; and
  `LIB$ADAWI` returns `LIB$_NORMAL` or `LIB$_INTOVF`, not `SS$` codes
  (`vax-macro32-backend.md`, section 22.8).

Left out, as proposal 7 says. Process control is a part of its own. The
inventory's `LIB$` entry is marked done, and with it step 5's supported
tier.

## Proposals, part 11: process control (2026-10-16)

The part the user set apart from part 10: `LIB$`'s routines that start or
give way to another process or image, `LIB$SPAWN`, `LIB$ATTACH`,
`LIB$DO_COMMAND` and `LIB$RUN_PROGRAM`, with `LIB$PUT_COMMON` and
`LIB$GET_COMMON`, which carry data from one image to the next. The facts
come from the *VMS RTL Library (LIB$) Manual* (`AA-LA76A`, 5.0), LIB-17,
LIB-124, LIB-332 and LIB-382. **Approved by the user, 2026-10-16**, all
eight.

What the generated declarations already have, all matching the manual:
- `LIB$SPAWN`, with each argument optional (`NIL`, or 0 for the two
  passed by value). Its AST is typed `AsynchronousTraps.Routine` (step
  6), and its `completion_status_address` is a `SYSTEM.ADDRESS` *by
  value*, as LIB-384 says: the address where VMS later writes the
  status. 5.5-2's SDL adds a thirteenth argument, `table`, after the
  5.0 manual's `cli`.
- The flags are `CLIDEF`'s `CLI$M_NOWAIT`, `NOCLISYM`, `NOLOGNAM`,
  `NOKEYPAD`, `NOTIFY` and `NOCONTROL`.
- `LIB$ATTACH`, `LIB$DO_COMMAND`, `LIB$RUN_PROGRAM`, `LIB$PUT_COMMON` and
  `LIB$GET_COMMON`, each a string or a process id.

Each needs DCL: a program run without a CLI, as a subprocess or detached
process run directly, gets `LIB$_NOCLI`.

1. **A small VMSLIB module, `Subprocesses`, for `LIB$SPAWN`.** One
   problem makes the bare routine unsafe in Oberon. With `CLI$M_NOWAIT`,
   VMS writes the completion status into the program's memory *later*,
   when the subprocess ends (LIB-384: "Your program must ensure that
   the address is still valid when the longword is written"). A local
   is gone by then. A heap object is safe only while the program holds
   it, and if it does not, the collector frees memory that VMS later
   writes. The module settles that once:
   ```
   Subprocess* = POINTER TO SubprocessDesc;  (* fields hidden *)
   PROCEDURE Run*(command, input, output: ARRAY OF CHAR; options: SET;
                  VAR completion: SYSTEM.INT32): SYSTEM.INT32;
   PROCEDURE Start*(command, input, output: ARRAY OF CHAR; options: SET;
                    VAR s: Subprocess): SYSTEM.INT32;
   PROCEDURE Done*(s: Subprocess): BOOLEAN;
   PROCEDURE Wait*(s: Subprocess): SYSTEM.INT32;
   PROCEDURE Stop*(s: Subprocess): SYSTEM.INT32;
   PROCEDURE Id*(s: Subprocess): SYSTEM.CARD32;
   ```
   - `Run` spawns and waits. VMS writes the completion status before
     the call returns, so the address of a local is enough, and
     `completion` is the subprocess's final `$STATUS`.
   - `Start` spawns with `CLI$M_NOWAIT`. The status cell and an event
     flag (`EventFlags.Get`) belong to the `Subprocess`, which the module
     keeps on a list of its own until `Wait` has seen it end. So the
     program may drop `s`, and the collector never frees the cell under
     VMS.
   - `Done` says whether the event flag is set, without waiting. `Wait`
     waits for it (`$WAITFR`), frees the flag, takes the `Subprocess` off
     the list, and returns the completion status.
   - `Stop` deletes the subprocess (`$DELPRC`). `Wait` then gives the
     status VMS reports for a deleted process, which the guest shows.
   - An empty `command`, `input` or `output` is omitted (`NIL`). With
     `output` given, the subprocess's `SYS$OUTPUT` and `SYS$ERROR` go to
     that file.
   - `options` holds the module's `noSymbols`, `noLogicalNames` and
     `noKeypad`, which become `CLI$M_NOCLISYM`, `NOLOGNAM` and `NOKEYPAD`.
     `NOWAIT` is chosen by `Run` or `Start`. `NOTIFY` and `NOCONTROL`
     (a broadcast message and a prompt's line feed) are left to the
     generated declaration.
   - A subprocess's own name, prompt and CLI are left to the generated
     declaration too; VMS makes a unique name.

   With a completion AST, a program uses the generated `LIB$SPAWN`
   itself, under step 6's rules for AST routines, and keeps its status
   cell in a global. The module's comment says so, and the fixture does
   it once.

2. **`LIB$DO_COMMAND` and `LIB$RUN_PROGRAM`: the generated declarations,
   no module.** Both end the image at the call; nothing returns on
   success.
   - The image exits by `$EXIT` (LIB-332), so poc's exit handler runs:
     finalizers, and `Out`'s last line not ended by `Ln`. The guest shows
     that it does.
   - `LIB$PUT_COMMON` and `LIB$GET_COMMON` pass a string to the next
     image, up to 252 characters. They are the manual's way to give
     `LIB$RUN_PROGRAM`'s program its arguments (LIB-333). It also says
     the practice "is not recommended", so the module's comment points
     to a foreign command line or a logical name instead.

   A module would add only a wrapper around one string each.

3. **`LIB$ATTACH`: the generated declaration, checked by hand.** It moves
   the terminal to another process of the job, and the caller hibernates
   until something attaches back. A fixture cannot do that unattended:
   `vax-do`'s session would lose its terminal. A hand check like
   `SmgScreen`'s is the proof: a program spawns a subprocess with
   `NOWAIT`, attaches to it, the user types `ATTACH` back with the
   program's process name, and the program goes on. Recorded in "Part
   11 done".

4. **Subprocesses and ASTs.** The two facts the manual gives, written
   into `Subprocesses`' comment and `vax-macro32-backend.md` section 22:
   - `Run`, and any `LIB$SPAWN` without `NOWAIT`, hibernates **in
     supervisor mode**. So the program's user-mode ASTs, a `Timers.After`
     among them, wait until the subprocess ends (LIB-386).
   - A completion AST runs under step 6's rules: at AST level, as any
     other.

5. **Fixture `vax-subprocesses`, on the guest:** one program,
   `SpawnUse`, prints only what does not change from run to run, never a
   PID or a generated process name.
   - **`Run`:**
     - a `WRITE SYS$OUTPUT` with its output to a file, which the program
       then reads by `Files` and prints;
     - `EXIT 44`, completion status 44;
     - a command with no output file, whose line appears in the program's
       own output;
     - a symbol and a process logical name defined by `Symbols` and
       `LogicalNames`, seen by the subprocess, and not seen with
       `noSymbols` and `noLogicalNames`;
     - `input`, a command file written by the program, run through.
   - **`Start` and `Wait`:** two subprocesses at once, each with its own
     output file, waited for in turn. Then a third, `WAIT 00:01:00`,
     stopped by `Stop`, and `Wait`'s status for it.
   - **`LIB$SPAWN` itself** with `NOWAIT` and a completion AST. The AST
     routine records its parameter and the status, and the main line
     sleeps by `Timers.Sleep` until it has run.
   - **`LIB$SPAWN` itself** with a process name, twice. The second is
     `SS$_DUPLNAM`; the first is then waited for.
   - **The chain:** `LIB$PUT_COMMON` of a line, then `LIB$RUN_PROGRAM` of
     a second program, `ChainedUse`, which `LIB$GET_COMMON`s it, prints
     it, and ends by `LIB$DO_COMMAND` of a `WRITE SYS$OUTPUT`.
     `guest-run.com` builds both programs and shows what follows each
     exit. A last line written with no `Ln` before `LIB$RUN_PROGRAM`
     shows that the exit handler ran.

6. **Checked on the guest as written, not before:**
   - what status `Wait` gives for a subprocess `Stop` deleted;
   - whether `LIB$DO_COMMAND`'s command runs, inside `guest-run.com`'s
     procedure, before the procedure's next line, and whether that line
     runs at all;
   - whether `LIB$RUN_PROGRAM`'s image runs, and with which `$STATUS`;
   - whether the POC account's subprocess quota (`PRCLM`) allows two at
     once, or `SS$_EXQUOTA`;
   - where the output of a subprocess with no output file goes when the
     program is run by `vax-do`.

   `Subprocesses`' comment states the answers.

7. **Left out:**
   - `$CREPRC`, detached processes and `LOGINOUT`: a process without
     DCL, which none of these routines serves.
   - `$FORCEX`, `$SUSPND` and `$RESUME` of a subprocess, and `$GETJPI`
     on it beyond its PID: callable through `STARLET`, not checked.
   - `CLI$M_NOTIFY`, `CLI$M_NOCONTROL`, a subprocess's prompt and its CLI
     or command table.

8. **The documents:**
   - "Part 11 done" here;
   - the inventory's `LIB$` entry, process control done;
   - `vax-macro32-backend.md` section 22, proposal 4's two facts;
   - `rtl/vax/vmslib/README.md` for `Subprocesses`;
   - `PLAN.md` step 5, "Part 12".

   `vax-vmslib`'s list gains `Subprocesses`, and `vax-asts` and
   `vax-conditions-handlers` build it with every other VMSLIB module.

## Part 11 done: what was implemented (2026-10-16)

Proposals 1 to 8 as written, but for a slip in the fixture that the guest
caught (below):
- **`rtl/vax/vmslib/Subprocesses.Mod`**, compiled under `-O2` and `-OC`
  by `vax-vmslib` and put in VMSLIB. It declares its own `LIB$SPAWN`
  with each string a descriptor's address, 0 when omitted, so that one
  call serves every combination of empty arguments; `Describe` makes a
  descriptor only for a string that is not empty. `Start` takes its event
  flag from `EventFlags.Get`, and gives it back if the spawn fails.
- **Fixture `vax-subprocesses`** (`SpawnUse` and `ChainedUse`), which
  passes on the guest. `vax-vmslib`, `vax-asts` and
  `vax-conditions-handlers` build `Subprocesses` with every other VMSLIB
  module, and their VMSDEF gains `CLIDEF`, which it imports.

The first guest run hung until `vax-do` gave up. The fixture gave its own
`LIB$SPAWN` the process name `POC_SPAWN_FIXTURE`, 17 characters, and a
process name has at most 15, so the spawn failed with `SS$_IVLOGNAM`, no
event flag was ever set, and the `$WAITFR` for it never returned. The
fixture now uses `POC_SPAWN_TEST`, adds a third call with the long name to
show `SS$_IVLOGNAM`, and waits for the flag at most 30 seconds, so that a
spawn that fails cannot hang it again. `Subprocesses.Wait` waits only on a
`Subprocess` whose spawn succeeded, since `Start` returns `NIL` for one
that failed.

What the guest showed, proposal 6's points first:
- **`Wait` after `Stop`** gives `SS$_NORMAL` for the subprocess `$DELPRC`
  deleted, not a condition that says it was deleted.
- **`LIB$DO_COMMAND`, inside `guest-run.com`'s procedure**, ends the
  image, and its command runs before the procedure's next line, which
  then runs as usual, with `$STATUS` `%X00010001`.
- **`LIB$RUN_PROGRAM`** runs its image in place of the caller's: the
  `Show` after the call never printed, and `ChainedUse` printed the line
  `LIB$PUT_COMMON` had given it, 30 characters.
- **`PRCLM`** allows the POC account two subprocesses at once.
- **A subprocess with no output file** writes to the caller's
  `SYS$OUTPUT`, here `vax-do`'s log file: the line appears in the
  program's own output, and so does the `%SYSTEM-F-ABORT` message DCL
  prints for `EXIT 44`.
- **The exit handler runs at a chain**: the line written with no `Ln`
  before `LIB$RUN_PROGRAM` appears, on a line of its own.

And:
- A symbol and a process logical name are seen by the subprocess (`F$TYPE`
  gives `STRING`) and not with `noSymbols` and `noLogicalNames`.
- An input file's commands run, and its `EXIT 3` is the completion status.
- The completion AST runs with its parameter, 7, and the status cell is
  written before it.

`Subprocesses`' comment states these answers, as proposal 6 says.
`LIB$ATTACH` is left to a hand check with the user (proposal 3), not yet
made. The inventory's `LIB$` entry is marked done, with process control.
