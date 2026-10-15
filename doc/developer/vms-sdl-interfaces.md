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
   | anything by another descriptor | `x: SYSTEM.ADDRESS`, a descriptor built by hand |

   - The quadword row lets one formal take a `HUGEINT`, an
     `IOStatusBlock`, a FAB or an item list (proposal 7). `SYS$QIOW`'s
     `P1`, which SDL calls `IN`, is written `VAR` when the generator is
     told so by a short list of known exceptions in `sdloberon.c`, with
     a comment; otherwise `x-` still passes a variable's own address,
     so a read works.
   - A routine is `SYSTEM.ADDRESS` until step 6 decides how an Oberon
     procedure is given to VMS (part 1's `CheckVmsCallbackType` already
     checks a procedure type). `SYSTEM.ADR(P)` gives its address now.
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
