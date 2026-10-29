# The VAX/VMS MACRO-32 backend (Phase 15) — design

Status: written before any code (2026-10-05) for `PLAN.md` Phase 15, and
kept as the record of its decisions; the phase was done on 2026-10-08
(`doc/history/phases/phase-15.md`). Sections 13-17 hold Phase 16's
design and decisions, done on 2026-10-12
(`doc/history/phases/phase-16.md`). Section 18 begins Phase 17's.
Each section says what the manuals
fix (a fact, with its source) and what poc chooses: **Decided** where
the user has agreed (2026-10-05), otherwise a proposal. The questions
still open are in §11, and the proposed order of work in §12.

## 1. What Phase 15 is

`PLAN.md` Phase 15: `VaxTypes.Mod`, `VaxCodeGenerator.Mod` and a stub
`VaxToolchainDriver.Mod`, emitting MACRO-32 for **exactly Phase 8's
vertical slice** - integer types `SHORTINT` to `HUGEINT`, `CHAR`, `BOOLEAN`
and `SET`; module-level and local `VAR`s; fixed arrays and base-less records
as values; ordinary (not type-bound, not nested) procedures; IF, CASE, WHILE,
REPEAT, FOR, LOOP/EXIT and RETURN; the predeclared procedures that need no
heap (`ABS`, `ODD`, `CHR`, `ORD`, `CAP`, `LEN`, `INC`, `DEC`, `COPY`,
`HALT`, and, added with the user 2026-10-08, `INCL`, `EXCL`, `SHORT`,
`LONG` and `ASH`); runtime traps; external procedures; several modules and the
program's entry (`doc/history/phases/phase-08.md`, "Explicit non-goals" and
steps 5-12). Not `REAL`/`LONGREAL` (Phase 8 left them to Phase 9), pointers,
`NEW`, the collector, type-bound procedures, open arrays or nested
procedures: Phase 16 step 3 brings those, with record extension, record
field initializers, record and array literals, and `SYSTEM.SET64` (added
with the user 2026-10-08).

"Done" is hand-reviewed `.mar` output checked in as
`test/conformance/*/expected-vax.mar`-style fixtures, each with a reviewer's
rationale comment, not an automated pass/fail; assembling, linking and
running are Phase 16's.

## 2. Sources, and the release rule

The target is VAX/VMS 5.5-2. Every fact below comes from a manual of the 5.5
documentation set - which, for most programming manuals, is a 5.0 or 5.4
edition shipped unrevised (`vax-vms-manuals-to-get.md`, Priority 3) - or is
marked as from something else. Short names used here, all under
`~/Reference/Computer/`:

| Short name | Manual |
|---|---|
| MACRO | `AA-LA89B`, *VAX MACRO and Instruction Set Reference Manual*, 5.4 (June 1990), the 5.5 kit's edition |
| CallStd | `AA-LA66B`, *Introduction to VMS System Routines*, 5.4, chapter 2: the VAX Procedure Calling and Condition Handling Standard |
| Linker | `AA-LA62A`, *VMS Linker Utility Manual*, 5.0, the 5.5 kit's edition |
| LIB | `AA-LA76A`, *VMS RTL Library (LIB$) Manual*, 5.0, the 5.5 kit's edition |
| VAX C | `AA-L370D`, *Guide to VAX C*, 3.0 (January 1989) - a layered product, not part of the base kit |
| OCS 1994 | `AA-PV69B`, *OpenVMS Calling Standard* (March 1994, 6.1): later than 5.5-2, for explanation only |

**The development system.** A SIMH `microvax3900` running VMS, with a user
`POC` for this work (2026-10-05). It reports
`V5.5-2H4` on a "VAXserver 3900 Series" (`F$GETSYI("VERSION")`,
`F$GETSYI("HW_NAME")`), and has `SYS$SYSTEM:MACRO32.EXE` (dated 17-OCT-1991),
`LINK.EXE`, `SYS$LIBRARY:STARLET.MLB`, `STARLET.OLB` and `LIBRTL.EXE`: the
assembler is in the base system. 5.5-2H4 is the later hardware release of
5.5-2, not 5.5-2 itself. **Decided**: this system is used for development;
the exact version of the machine poc will finally run on is still to be
checked by the user, and its release notes added to
`vax-vms-manuals-to-get.md` if it differs.

## 3. What MACRO-32 requires of the text poc writes

Facts:

- **Symbols** are letters, digits, `_`, `$` and `.`, not starting with a
  digit, and "no more than 31 characters long" (MACRO 3.3.2). **Lowercase
  letters are the same as uppercase**, except in ASCII strings (MACRO 3.1).
- **By DIGITAL's convention `$` marks DIGITAL's own names, and a global
  symbol should not contain `.`**, since languages such as FORTRAN cannot
  name it (MACRO 3.3.2).
- A symbol is local to its module unless it is defined with `::` or `==`, or
  named by `.GLOBAL`, `.ENTRY` or `.WEAK` (MACRO 3.3.3). `.ENTRY` always
  makes a global symbol (MACRO 6, `.ENTRY`).
- **Local labels** `nn$` run from 1 to 65535; DIGITAL asks users to keep to
  1-29999, since the assembler makes 30000-65535 for macros. A local label
  is valid only within its *local label block*, which ends at the next
  user-defined label or `.PSECT` (MACRO 3.4).
- **Program sections**: at most 254 named ones per assembly; a name is up to
  31 characters. Attributes include `EXE`/`NOEXE`, `WRT`/`NOWRT`,
  `SHR`/`NOSHR`, `PIC`/`NOPIC`, `CON`/`OVR`, `LCL`/`GBL`, and an alignment
  from `BYTE` to `PAGE` or 0-9 (a power of two); `.ALIGN` cannot ask for
  more than its section's alignment. Sections of the same name and
  attributes, `CON`, are concatenated by the linker; the same name with
  different attributes is an error (MACRO 6, `.PSECT`).
- **Alignment**: "Although most instructions can use byte alignment of data,
  execution speed is improved" by aligning words, longwords and quadwords
  to their size (MACRO 6, `.ALIGN`, note 2).
- **Entry points**: `.ENTRY name, mask` stores a 2-byte register save mask;
  bits 0, 1, 12 and 13 (R0, R1, AP, FP) must be clear; bit 14 (`IV`)
  enables the integer overflow trap and bit 15 (`DV`) the decimal one
  (MACRO 3.6.2.2, 6 `.ENTRY`). A routine entered by `JSB` has no mask and
  is not defined with `.ENTRY`.
- **The program's start** is the transfer address on `.END`; it must be in
  an `EXE` section, and exactly one module of an image may give one (MACRO 6,
  `.END`).
- **Branches**: a conditional branch and `BRB` have a byte displacement
  (-128 to +127), `BRW` a word (-32768 to +32767), measured from the next
  instruction (MACRO 5.4). Nothing in the manual says the assembler
  lengthens a branch that does not fit, and it does not (§3.1).

### 3.1 Checked on the development system

Two probes were assembled with `MACRO/OBJECT/LIST` on the development
system (VAX MACRO V5.4-3) on 2026-10-05:

- **Case is folded**: labels `Foo:` and `FOO:` in one module are
  `%MACRO-E-MULDEFLBL, Multiple definition of label`.
- **A symbol over 31 characters is only a warning**,
  `%MACRO-W-ILLSYMLEN, Symbol exceeds 31 characters`, and the assembly
  goes on. So the assembler does not protect poc from a name that is too
  long; poc checks every name itself (§5).
- **No branch is lengthened**: a `BRW` and a `BEQL` 40,000 bytes from
  their target are each `%MACRO-E-BRDESTRANG, Branch destination out of
  range`.
- **`JMP L^label`** to a label 40,000 bytes ahead assembles as `17 EF` and
  a longword displacement, 6 bytes; a symbol of exactly 31 characters as an
  `.ENTRY`, and the three program sections of §6 with exactly the
  attributes written, are accepted.
- **A source must be sent in ASCII mode.** Copied by FTP in binary mode, a
  `.MAR` becomes a file of fixed-length 512-byte records; in ASCII mode
  (curl's `--use-ascii`), variable-length records with carriage-return
  carriage control, an ordinary VMS text file.

Proposals:

- **Every symbol poc writes is uppercase**, and every name poc makes up is
  checked against the 31-character limit before it is written (§5).
- `JMP dst` takes any address (MACRO 9, `JMP`). In relative mode the
  assembler picks the shortest displacement for a target already defined;
  for one defined later, or in another program section, it uses the
  `.DEFAULT` length, unless a specifier (`B^`, `W^`, `L^`) says which
  (MACRO 5.2.1).
- **Branches**: the conditional branches are short, so, as compilers do, a
  condition is tested with a short branch whose target is a jump. Within a
  statement's own short code (a relational's condition, a `&`/`OR` short
  circuit) poc uses byte branches only where the distance is fixed and
  small. Every jump to a statement label (loop heads, `ELSIF` chains,
  `EXIT`, `RETURN`) is an inverted conditional branch over `JMP L^label`,
  or a plain `JMP L^label`, which reaches anywhere, so no procedure is too
  long. `BRW` (word displacement) is shorter but needs the distance known;
  Phase 18, which writes its own instructions and knows every address,
  chooses the shortest form. Done (step 4): a condition jumps by the
  branch for staying, over the jump - `Bxx L_n`, `JMP L^label`, `L_n:` -
  and `EXIT` is a plain `JMP L^` to its loop's end.
- **Labels**: poc's own labels are generated, unique, local symbols
  (`L_<n>`), not `nn$` local labels, whose block ends at every user-defined
  label and would be hard to reason about across a long procedure.

## 4. Data

Facts (CallStd 2.8.1): byte, word, longword and quadword integers, signed
(two's complement) and unsigned; F_floating (32 bits), D_floating and
G_floating (64), H_floating (128). VAX C lays out a structure with **no
implicit alignment** - each member at the next byte - and says "this
alignment of structure members is a VAX C convention and is also followed
by all other VAX languages"; `#pragma member_alignment` changes it (VAX C
8.9).

| Oberon type | `-O2` | `-OC` | VAX representation |
|---|---|---|---|
| `BOOLEAN` | 1 | 1 | byte, 0 or 1 |
| `CHAR`, `SYSTEM.BYTE` | 1 | 1 | byte |
| `SHORTINT` | 1 | 2 | byte / word |
| `INTEGER` | 2 | 4 | word / longword |
| `LONGINT` | 4 | 8 | longword / quadword |
| `HUGEINT` | 8 | 8 | quadword |
| `SET` | 4 | 4 | longword, element *i* is bit *i* |
| `SYSTEM.ADDRESS` | 4 | 4 | longword (the VAX's 32-bit address) |
| `REAL` | 4 | 4 | F_floating longword |
| `LONGREAL` | 8 | 8 | G_floating quadword |

Sizes are `MemoryLayout.BasicSize`'s, word size 4.

Proposals:

- **Decided. Layout: `MemoryLayout`'s rule, unchanged** - natural alignment capped at
  the 4-byte word - not VAX C's byte packing. It is what poc's front end
  already computes for `SIZE` and offsets, and aligned data is faster
  (MACRO, above). Records passed to a VMS routine must match its layout;
  that matters only for external procedures, and only from Phase 17, which
  can add a packed-record attribute if one is needed (§11, question 5).
- **Decided. Only `-O2` for the VAX at first.** Under `-OC` `LONGINT` is a quadword,
  which the VAX has few instructions for (below), and `INTEGER` the
  longword. `-OC` is accepted later if wanted (§11, question 4).
  **Changed (the user, 2026-10-09): `-OC` too**, since poc's own source
  needs it (§14).
- **`HUGEINT`** is a quadword, low longword first. The VAX has `MOVQ`,
  `CLRQ` and `ASHQ` but no quadword add, subtract, compare or multiply
  (none in MACRO's instruction set): `+` and `-` are `ADDL2`/`ADWC` and
  `SUBL2`/`SBWC` pairs, comparison is high longwords signed then low
  longwords unsigned. `*`, `DIV` and `MOD` call routines of poc's runtime,
  since `EMUL` is only 32 x 32 -> 64 bits and `EDIV` 64 / 32 -> 32, and
  `LIB$EMUL`/`LIB$EDIV` only wrap those instructions (LIB, `LIB$EMUL`,
  `LIB$EDIV`). Phase 15 writes the calls; Phase 16 writes the routines.
- **Done (step 6): arrays and records** take `MemoryLayout`'s sizes,
  offsets and alignment, as above. A module variable is `.BLKB <size>`
  after the `.ALIGN` of its alignment, a local the same bytes of the
  frame, aligned so. A record with a base type or a field initializer is
  Phase 16's, as is an open array. (Phase 16 step 3 lowers extension,
  §14.)
- **Done (step 3): real types.** `REAL` is F_floating and `LONGREAL`
  G_floating (§14, item 9). VAX C chooses the `LONGREAL` format with a
  qualifier, `/G_FLOAT`, defaulting to D_floating (`/NOG_FLOAT`), and a
  program compiled with `/G_FLOAT` links against a different run-time
  library (VAX C, the `CC` command's `/G_FLOAT` qualifier). poc needs G
  for its own folding (§14, item 9); a D option can come later. The VAX
  formats have no infinities or NaNs, so a real overflow or division by
  zero is the hardware's fault (`language-extensions.md`, "Overflow,
  division and reals").

## 5. Names

What has to hold: every global symbol is at most 31 characters, uppercase
(MACRO folds case, so `Foo` and `foo` would otherwise be the same symbol),
built from `A`-`Z`, `0`-`9`, `_` and `$`, and two different Oberon names
never give the same symbol, within a module or across a link. Oberon
identifiers may contain `$` and `_` (`language-extensions.md`, "Underscores
and dollar signs in identifiers"), and module names are often long (`PLAN.md`, "Naming
convention"). An external procedure's linkage name is the exception: it is
written verbatim, never mangled, since it must match the real symbol
(`language-extensions.md`, "External procedures").

The LLVM backend's names show what needs one (`LLVMCodeGenerator.Mod`):
`Module.name` for a variable or procedure, `Module.Outer.Inner`,
`Module.Type.Proc`, `Module_init`, constants, type descriptors and
module keys.

**Decided: a readable stem plus a hash, for every global symbol poc makes
up.**

- The *full name* is the LLVM backend's qualified name, case kept:
  `Ropes.Length`, `Ropes.Tree.Length`.
- The symbol is `<stem>_<hash>`. The hash is a fixed-width code of the full
  name, case included - for example 40 bits of FNV-1a written as 8
  characters `0`-`9`, `A`-`V` - so `Foo` and `foo` differ. The stem is the
  full name uppercased, each character outside `A`-`Z`, `0`-`9`, `_` and
  `$` turned into `_`, cut to the 22 characters that leave room for
  `_` and the hash. `Ropes.Length` might become `ROPES_LENGTH_0K7Q3M2A`.
  The stem is only for a human reading a map or a traceback.
- **The exception: a module's initializer is `<MODULE>_INIT`**, unhashed
  (decided 2026-10-06; why, §5.1): the module name uppercased, then
  `_INIT`, so `Ropes`'s is `ROPES_INIT`. It can never equal a made-up
  symbol, whose last nine characters are always `_` and eight base-32
  digits, and `_INIT` is not. So a module name is at most 26 characters,
  and a longer one is an error at compile time, never hashed. Two module
  names that differ only in case give one symbol, which the closure check
  of §5.1 reports.
- **Collisions are checked, not just made unlikely.** Within a module, poc
  keeps the symbols it has written and stops with an error if two full
  names give one symbol. Across modules, see §5.1: the linker's "multiply
  defined" alone is not enough once modules come from object libraries.
  A fixture set of long and colliding names (as `PLAN.md` asks) shows the
  scheme in action. With 40 bits, a collision is not expected by accident
  in any real program, but one is easy to make on purpose (§5.1).
- A name that is not exported and not otherwise needed outside its module
  (a private procedure, a local constant) is a *local* symbol, so its
  symbol only has to be unique in its module; it uses the same scheme
  for simplicity.
- An external procedure's linkage name longer than 31 characters, or with
  a character MACRO cannot take, is an error at compile time.
- **Program sections** are not per module: every module uses the same few
  names (§6), which the linker concatenates. They are spelled without `$`,
  DIGITAL's mark.

Rejected: a numbering scheme (`M17_P4`), which needs one registry of
numbers across separately compiled modules; truncation without a hash,
which collides on long names with a common start, as poc's own module
names have (`LLVMCodeGenerator`, `LLVMToolchainDriver`).

### 5.1 Collisions across a link

**Decided (2026-10-06)**: the user accepted this section as proposed
(2026-10-05).

**A collision can be made on purpose.** A birthday search over 12-letter
random suffixes found, after 664,867 names (seconds, well under 4 GB):

```
VaxNameClash.collisionPuRhnmwOfQAB  ->  VAXNAMECLASH_COLLISION_VA2IG0SM
VaxNameClash.collisionTqMUQStWWdKp  ->  VAXNAMECLASH_COLLISION_VA2IG0SM
```

both checked against the §5 scheme. (A first search over *5-letter*
suffixes found none and grew to 34 GB before the kernel's OOM killer
stopped it: modulo 2^40 the FNV prime is `0x1B3`, so FNV-1a of a few
bytes is nearly a weighted sum of them with weights below 2^40, and short
letter suffixes almost never cancel. Long suffixes mix properly.) By
accident a collision stays unlikely - about n^2/2^41 for n names sharing
a 22-character stem - and a deliberate one is no threat: whoever writes
the source already controls the program. So the aim is not a longer hash
(every hash bit costs a stem character; 17+13 would give 65 bits and a
less readable map, and still no guarantee) but that **every collision that
matters fails the build, loudly**.

**Where a collision can link silently.** poc modules on VMS will be
distributed as source, as `.sym` and `.mar`, as `.sym` and `.obj`, or in
libraries, which will be VMS object libraries (`.OLB`). Two modules
defining the same symbol in one link is `%LINK-W-MULDEF` - a *warning*;
the image is still written. Worse, the linker takes a module from a
library only to resolve a symbol still undefined. If `A` defines `X`, and
library module `B` defines `Y` with the same symbol, a reference to `B.Y`
is resolved by `A`'s `X`, `B` is never loaded, and nothing is reported: a
wrong program with no diagnostic.

**The proposed fix, in three layers:**

1. **The link itself is sound.** Every import forces its module to be
   loaded: an importer calls each import's `_init` (§6), so if the `_init`
   symbol is defined only by that module, the linker must take the module
   from its library, all its global symbols enter the link, and a
   collision becomes `MULDEF` instead of a silent binding. Every build
   procedure poc writes or ships treats `MULDEF` as fatal (the `LINK`'s
   `$STATUS` severity checked). This holds even for a `LINK` command
   written by hand, as long as `MULDEF` is not ignored.
2. **A readable error before the link.** Every distribution form includes
   a `.sym`, or produces one, since importers need the interface, so the
   import closure can always be computed from `.sym` files. **The `.sym`
   is not changed** (amended 2026-10-06): every full name the backend
   hashes - the module's, each exported object's, and the type names
   behind type-bound procedures and type descriptors, unexported types
   an importer's layout needs included - is already in it, and
   `MakeSymbol` is deterministic, so the check recomputes each symbol
   from the `.sym` as it is. At link time poc (or a separate check for
   hand-built links) walks the main module's import closure and stops if
   two different full names have one symbol: "`A.X` and `B.Y` both give
   `..._VA2IG0SM`; rename one". Done (Phase 16 step 2) for the modules
   poc writes in one run, a program's (`-build`, `-emit-macro32`) or
   `-compile`'s: each module's exported variables and procedures enter one
   table as they are written, and a second full name with a symbol
   already there is an error at its declaration, in its own file
   (`vax-build`, `VaxBuildClash`); so are two modules whose names differ
   only in case. The check from `.sym` files, for modules compiled
   separately or in libraries, comes with them (Phase 17; done, section
   18.5).
   **The name scheme's version belongs to the VAX target, not to the
   interface.** A `.sym`'s text does not depend on the target (it is
   stored per target and size model, `lib/poc/<triple>/<O2|OC>/`, but
   reads the same everywhere), and a module's key is the hash of its
   `.sym` bytes (`ModuleInterface.Mod`, "Module keys"), so a field in it
   would change every module's key on every target, LLVM's included,
   for no LLVM use. Instead the version is carried where the LLVM
   backend keeps its per-target facts: in a symbol each VAX object
   defines and its importers refer to, as `<M>.-target.<triple>` does on
   LLVM, so objects made with different schemes fail to link, and in a
   VAX library's manifest, so such a library is refused at import.
   **Decided (2026-10-08, §11 question 8): one symbol carries both**,
   `POC_K1_` and the module's key, its 16 hex digits uppercased, as
   `.IDENT` shows them (23 characters): the `1` is the name scheme's
   version. The module defines it, `POC_K1_<KEY> == 0`, a global absolute
   symbol; each importer declares it `.EXTERNAL`, though nothing refers
   to it, which is enough for `LINK` to report it undefined
   (`%LINK-W-NUDFSYMS`, checked on the development system) when the
   module linked is not the one the importer was compiled against, or
   was made with another scheme. It never equals a hashed symbol (no `_`
   nine characters from its end) or a `<MODULE>_INIT` or `_MAIN`; a map
   shows the key, not the module's name, and `.IDENT` ties the two.
3. **Within a module**, as §5 says: its own definitions and the imported
   names it references, checked by poc at compile time, with source
   positions. Done (step 8): an imported variable or procedure enters
   the module's table of names under its home module's full name when
   first used, so `A.X` and an imported `B.Y` with one symbol are an
   error at the use (`vax-emit-errors`, `VaxClashBetweenModulesA`).

Details this depends on:

- **Module-level symbols must never collide with each other.** If `A`'s
  and `B`'s `_init` symbols collide, `B` is never loaded and layer 1 fails
  silently. Module names are unique in a program anyway, so the
  initializer's symbol is unhashed, `<MODULE>_INIT` (§5, decided
  2026-10-06), and the closure check treats a collision between
  module-level symbols - two module names differing only in case - as an
  error.
- **Private objects are local symbols** (`label:`, not `label::`), so they
  never enter a link; what can collide across modules is only exports and
  compiler-made globals.
- The Librarian probably reports a module whose global symbol is already
  in the library (`LIBRARY/INSERT`, `DUPGLOBAL`) - **not yet checked** on
  the development system. It sees only one library, so a collision
  between two libraries, or a library and an `.obj`, still rests on
  layers 1 and 2.
- The LLVM targets do not shorten names, and the `.sym` is unchanged, so
  nothing in §5.1 changes the LLVM backend.

## 6. A module's layout

Proposal, one `.mar` file per module:

```
        .TITLE  Ropes
        .IDENT  /<module key>/
        .PSECT  POC_CODE,  PIC,SHR,NOWRT,EXE,LONG
        .PSECT  POC_CONST, PIC,SHR,NOWRT,NOEXE,QUAD
        .PSECT  POC_DATA,  NOPIC,NOSHR,WRT,NOEXE,QUAD
        ...
        .END
```

- `POC_CODE` holds the procedures, `POC_CONST` string and structured
  constants, `POC_ADDR` (`PIC,NOSHR,NOWRT,NOEXE,LONG`, defined where it
  is first used, in a module with type descriptors) the constants that
  hold an `.ADDRESS`, so that `POC_CONST` stays shareable (§18, proposal
  5; Phase 17), `POC_DATA` the module's variables, zero-initialised (`.BLKB`)
  as on LLVM, and a flag "initialised". Done (step 3): each variable is a
  `.BLKx 1` of its size after an `.ALIGN` of its alignment, labelled by
  its §5 symbol, `::` (global) if it is exported and `:` (local)
  otherwise.
- Each procedure is an `.ENTRY` (§7). The module body is the procedure
  `<MODULE>_INIT` (§5), which returns at once if its flag is set, otherwise sets
  it, calls its imports' `_init`s in import order and runs the body. With
  no body the test is `BLBS` over the fixed 7 bytes to `RET`; a body can
  be any length, so then it is `BLBC` over a `RET` (§3; step 3). Done
  (step 8): each import's `_init` is `CALLS #0, G^<IMPORT>_INIT`, in the
  order of the `IMPORT` list, `SYSTEM` and a module of only constants and
  types left out, and with imports the test is always the `BLBC` form.
  The module also defines its key's symbol, `POC_K1_<KEY> == 0` (§5.1),
  and declares `.EXTERNAL` each import's `_init` and key, and every
  imported variable and procedure it uses.
- The **program's start** is one routine, written into the main module
  only, with `.END` naming it: it calls the main module's `_init` and
  returns `SS$_NORMAL` (1) in `R0`. `HALT(n)` and a trap end the program by
  a runtime routine (§9). How an exit status reaches DCL is Phase 16 step
  3c's to settle. **Decided (2026-10-08)**: it is `<MODULE>_MAIN`, an
  `.ENTRY` with an empty mask after the key, `CALLS #0, <MODULE>_INIT`,
  `MOVL #1, R0`, `RET`, then `.END <MODULE>_MAIN`; another module ends
  with a bare `.END`. The main module is the program's last (the one
  named on poc's command line). It is a routine, not a jump into
  `_INIT`, so that Phase 16 can run the modules' cleanup there first.
  Done (step 8).
- `.IDENT` carries the module key, so a map or `ANALYZE/OBJECT` shows which
  `.sym` the object was built from.

## 7. Procedures and calls

Facts (CallStd 2.2-2.7):

- A call is `CALLS #n, proc` after pushing the arguments last to first, or
  `CALLG arglist, proc`. The argument list is a longword count (low byte)
  followed by one longword per argument, the first at `4(AP)`; each is an
  immediate value (32 bits or less), an address (by reference) or a
  descriptor's address.
- A function value of 32 bits or less is returned in `R0`, of 64 bits in
  `R0`/`R1`; anything larger is returned through a hidden first argument.
- `R0` and `R1` are scratch; **`R2`-`R11` are preserved by the callee
  through its entry mask**, so that unwinding restores them; `AP`, `FP`,
  `SP` and `PC` are saved by `CALLx` and restored by `RET`. `FP` must
  always point at the frame and must not be changed in the body.
- A procedure allocates its locals by subtracting from `SP`; `RET` frees
  them. The stack above the frame belongs to the caller.
- `R1` carries a bound procedure value's *environment* when one is called
  (CallStd 2.6.1, 2.8.3: a bound procedure value is the entry address and
  an environment longword).
- The standard governs external interfaces; it "does not apply to calls to
  internal (local) routines or to language support routines" (CallStd 2.1).

Proposals:

- **Decided. One calling mechanism, the standard's, for every procedure** - Oberon's
  own as well as external - so a debugger traceback, a condition handler
  and stack unwinding work everywhere, and Phase 17's ASTs need nothing
  special. `PLAN.md` Phase 16 step 3b leaves "one convention for
  everything" open; this proposes it for Phase 15 and lets Phase 16 revisit
  it if speed needs `JSB` linkages for small internal routines.
- **Arguments**, for Oberon procedures: a value parameter of 4 bytes or
  less is passed by immediate value, sign- or zero-extended to a longword;
  a `HUGEINT` value parameter and a record or array value parameter are
  passed by reference, the callee copying it into its own frame unless it
  is read-only (`-` parameters: the reference is used directly); a `VAR`
  parameter is passed by reference. The arguments are evaluated left to
  right (Oberon requires none, CallStd 2.3.2.1 permits any) and pushed in
  reverse, so `n(AP)` of parameter *i* is `4*i`.
- **Decided (2026-10-06): left to right, as on LLVM**, so that a program
  whose arguments have side effects (`P(Next(), Next())`) does the same
  on both targets. Pushing as they are evaluated would be right to left,
  so each argument is stored, as it is evaluated, in an argument list
  built in the caller's frame (the count, then one longword per
  argument), and the call is `CALLG list, proc`, which costs no more than
  `CALLS`.
- **Decided (2026-10-06): a value parameter the body assigns to, or
  passes as a `VAR` argument or to `SYSTEM.ADR`, is copied to a local on
  entry**; any other is used where it is, at `n(AP)`. The argument list
  "must be treated as read-only data by the called procedure and can be
  allocated in read-only memory at the option of the calling program"
  (CallStd 2.3).
- **Decided (2026-10-06): an exported procedure is `.ENTRY name, mask`;
  a private one `name: .WORD mask`**, a local label and the mask as
  `.ENTRY` would write it, which `CALLS` and `CALLG` take the same way.
  `.ENTRY` always makes a global symbol (§3), and a private procedure's
  symbol is local (§5), so it never enters a link (§5.1).
- **Results**: up to 32 bits in `R0`, `HUGEINT` in `R0`/`R1` (low, high);
  Oberon functions return no structured values. A function that reaches
  its `END` calls `POC_TRAP` with code 12 (§9). Agreed 2026-10-06, as
  is: a value in `R0` or `R1` is spilled before a call, `R2`-`R5` being
  kept by the callee's mask; `HUGEINT` `*`, `DIV` and `MOD` call runtime
  routines, `.EXTERNAL`, provisionally `POC_HMUL`, `POC_HDIV` and
  `POC_HMOD`, their operands by reference and their result in
  `R0`/`R1`, the routines Phase 16's.
- **Locals** live below `FP`, at negative offsets, allocated with one
  `SUBL2 #size, SP` and cleared, as LLVM's are. Agreed 2026-10-06: the
  locals at fixed offsets next to `FP`, the spill slots below them, one
  `SUBL2` for both; a few longwords cleared by `CLRL`/`CLRQ`, more by
  `MOVC5 #0, ..., #0, size, -size(FP)` (which overwrites `R0`-`R5`,
  harmless on entry).
- **Registers**: the body uses `R0`-`R5` as scratch for expression
  evaluation; `R6`-`R11` are kept for later (register variables, or
  Phase 16's needs). The entry mask saves those of `R2`-`R11` the body
  writes. Done (step 3): a `HUGEINT` takes a pair `Rn`, `Rn+1`, low
  longword first; when no register is free the oldest one in use is
  spilled to a longword slot below `FP` (a pair to two) and used from
  there. The body is generated into a list before it is written, so the
  `.ENTRY` mask names exactly the registers written and one `SUBL2 #4n,
  SP` makes room for the most slots in use at once. Nothing in the
  architecture limits the scratch registers to `R0`-`R5` (CallStd:
  `R2`-`R11` are alike, each one written costing a save and a restore
  per call), and
  the string instructions (`MOVC3`, `MOVC5`, `CMPC3`, `LOCC`) themselves
  overwrite `R0`-`R5`. The proposal was that when step 6 brings `MOVCx`,
  the temporaries alive across one move up into `R6`-`R11` rather than
  spill. Done (step 6) otherwise: a move is a statement of its own - an
  assignment, or the copy of a parameter on entry - so nothing but its
  own operands' registers is in use across it, and anything that were
  would be spilled; `R6`-`R11` stay unused. A body with a `MOVCx` saves
  `R2`-`R5` in its mask.
- **Overflow**: the `IV` bit stays clear, so integer arithmetic wraps, as
  poc promises (`language-extensions.md`, "Overflow, division and reals").
  An opt-in overflow check could later set it.
- **Decided (2026-10-06): a symbol outside the module is named in
  general mode, `G^`**: an external `["VMS"]` procedure (`CALLG list,
  G^LIB$GET_EF`), poc's runtime routines (`G^POC_TRAP`, `G^POC_STRCMP`,
  `G^POC_HMUL`, ...), and, from step 8, an imported module's procedures
  and variables (done: `MOVL G^VAXMODBASE_TRACE_G4RP55C6, ...`, an
  element `G^...[R1]`, a field `G^...+2`). The linker makes a general mode operand relative when
  its symbol is relocatable and absolute when it is absolute (MACRO
  5.2.5), and the Linker manual says "to be safe, always use general
  addressing mode for any external reference" (Linker 4.2). Without it,
  a call of a routine in a shareable image is not position independent:
  `tools/vax-run` linking `vax-external` got `%LINK-W-SHRSYMREF,
  reference to symbol LIB$GET_EF is not position independent` (LIBRTL
  is a shareable image) and an image based at a fixed address. A symbol
  of the module itself keeps relative mode, the assembler's default.
- **External `["VMS"]` procedures**: the linkage name verbatim (§5); a
  value parameter of 4 bytes or less by immediate value, a `VAR` parameter
  by reference. Descriptors and an explicit choice of mechanism per
  parameter are Phase 17 step 5's (`PLAN.md`); a parameter needing one is
  an error until then. **Done (Phase 17 step 5, 2026-10-14)**: the
  mechanism follows the formal (`vms-sdl-interfaces.md`, part 1, and its
  record): `x-` by reference, an open `ARRAY OF CHAR` by a `CLASS_S`
  descriptor, another open array by reference, `NIL` an omitted argument
  (`VaxCodeGenerator.VmsArgument`).
- **Done (step 5)**, as decided above, with these details. A value
  parameter of a longword or less is read at its own width at `4n(AP)`;
  one the body may change - assigns, uses as a `FOR` variable, or passes
  as a `VAR` argument or to a predeclared procedure, which may change it
  - is copied to the frame on entry. A `VAR` parameter is `@4n(AP)`; a
  `HUGEINT` reached by address has its address moved to one of `R2`-`R5`
  first, its longwords being `0(Rn)` and `4(Rn)`, which `@4n(AP)` cannot
  name. The caller passes a `HUGEINT` value as the address of a copy in
  its frame, kept until the call returns. A value in `R0` or `R1` is
  moved up to a free one of `R2`-`R5` before a call, or else spilled;
  after a call in the right operand of `&` or `OR`, the left one's value
  is moved back where the path that skips the call left it. A value
  returned in `R0` is sign- or zero-extended to a longword, as
  arguments are. Not lowered yet: a procedure value or variable, a
  nested or type-bound procedure, an open-array parameter (Phase 16), a
  `["C"]` external (VAX/VMS takes `"VMS"`), and a `HUGEINT`, array or
  record value parameter of an external one (Phase 17 chooses its
  mechanism; step 5 did, `vms-sdl-interfaces.md`, part 1: such a value
  parameter is an error, and `x-` passes it by reference).
- **Done (step 6): array and record parameters.** A value parameter is
  passed by its address, the caller making no copy; the callee copies it
  into its frame on entry by `MOVC3`, after the locals are cleared,
  whether or not the body changes it, since otherwise a change to the
  variable passed, through a `VAR` parameter or a module variable, would
  show through it. A read-only one (`x-`) is not copied: its address is
  used, as a `VAR` parameter's. A string constant passed for an array is
  padded with zeros to the parameter's size, which is how much the callee
  copies. **Decided (2026-10-06): a `VAR` record parameter is its
  address only**, the slice having no extension; Phase 16 adds the type
  tag as a second longword (done: §14, item 5). A field reached through a parameter's
  address, `@4n(AP)`, has the address moved to a register first, `0(Rn)`,
  since `@4n(AP)` takes no displacement.
- **Nested procedures** are outside Phase 15. When Phase 16 takes them,
  `R1` as the environment value is the standard's own mechanism for a
  static link (`nested-procedures.md` §9 leaves the choice to this
  backend).

## 8. Expressions and statements

Proposals, by construct:

- **Decided (2026-10-06): integer arithmetic at the operation's own
  width** (`ADDB3`, `ADDW3`, `ADDL3`, ...), so wraparound happens at the
  type's width as poc promises, with no truncation afterwards; the other
  choice, longwords then truncated, cost a widening and a narrowing per
  operation. A narrower operand is first sign-extended (`CVTBW`, `CVTBL`,
  `CVTWL`), as Oberon types the operation (Appendix A). Done (step 3),
  with: the last operation of an assignment's value writes the variable
  itself when it is as wide (`x := y + z` is one `ADDW3`, `x := x + 1` an
  `INCW`); a constant expression is one immediate, folded by
  `ConstantEvaluator`. `HUGEINT` (§4): `+` and `-` are `ADDL2`/`ADWC` and
  `SUBL2`/`SBWC`, `-x` is `MNEGL` of each longword then `SBWC #0` for the
  borrow, and widening to it is `ASHL #-31` for the high longword; `*`,
  `DIV` and `MOD` are calls to poc's runtime, which wait for step 5.
- **`DIV` and `MOD`** floor: `DIVL3` truncates toward zero, then the same
  correction the LLVM backend makes (`LLVMCodeGenerator.GenerateDivMod`),
  the remainder by `EDIV` or by multiplying back. **A zero divisor traps
  in hardware** - "a divide-by-zero trap is forced after the execution of
  an integer ... division instruction that has a zero divisor" (MACRO
  8.4.1) - which matches poc's promise that `x DIV 0` ends the program.
- **Comparisons and `BOOLEAN`**: `CMPx` then a conditional branch; a
  `BOOLEAN` value is a byte 0 or 1. `&` and `OR` short-circuit with
  branches. Done (step 3), as a value: `CLRB` a register, `CMPx` (`TSTx`
  against zero), the branch for "false" over `MOVB #1` - signed for
  integers, unsigned for `CHAR`; a `HUGEINT` compares its high longwords
  signed, then its low ones unsigned. `&`/`OR` test the left value with
  `BLBC`/`BLBS`, a byte branch when the right operand is a variable or a
  constant (a fixed few bytes to skip) and otherwise a branch over `JMP
  L^` (§3). Every register in use is spilled first, so that no spill
  happens on one path only.
- **Conditions** of `IF`, `WHILE` and `REPEAT` (done, step 4) branch
  without making a value: a relation is `CMPx` and the branch for its
  opposite over `JMP L^` (§3), `~` takes the other sense, `&` and `OR`
  are jumps from each side (`a & b` false when `a` is), a constant
  condition is a jump or nothing, and any other `BOOLEAN` is `BLBC` or
  `BLBS`. `IF` tests each branch in turn, jumping to the next when it is
  false, each body ending in a jump to the end; `WHILE` tests at the
  head, `REPEAT` at the foot, `LOOP` jumps back, and `EXIT` to the end of
  the innermost `LOOP`.
- **`SET`**: a longword; `+` `BISL3`, `*` `MCOML` then `BICL3`, `-`
  `BICL3`, `/` `XORL3`; `IN` `BBS`/`BBC` (or `ASHL` and `BITL`) after a
  range check; `INCL`/`EXCL` `BBSS`/`BBCC`; a constant `{...}` an
  immediate. Done (step 3; `INCL` and `EXCL`, step 7b, are `BISL2` and
  `BICL2` of the element's mask, below): `IN` is `BBC` after `CMPL #31` and `BGTRU`
  (unsigned, so a negative element is out too), no check for a constant
  element; a constructor's variable element `e` is `ASHL e, #1`, a range
  `lo..hi` the bits of `ASHL lo, #-1` cleared of those of `ASHL hi, #-2`
  (`ASHL`'s count is a byte, the element's low one), and its constant
  elements one `BISL2` of an immediate. `SYSTEM.SET64` is outside the
  slice (done, §14 item 11).
- **`CASE`**: `CASEL`, the VAX's own table-driven case instruction, for a
  dense range of labels, and a chain of compares otherwise; a value with
  no label goes to the "no CASE label" trap (§9). Done (step 4): the
  selector is evaluated once, kept in a slot of the frame if it was in a
  register. The labels are dense when there are at least four values,
  they fill at least half of the range they span, the range is under
  4096, and the selector is not a `HUGEINT` (there is no `CASEQ`): then
  `CASEB`, `CASEW` or `CASEL` (the selector's width) with `#min` and
  `#max-min`, and a table of `.WORD` displacements, one per value, to a
  stub `JMP L^` of each arm, or of the no-label code, since a word cannot
  reach a long arm; `CASEx` falls through past the table when the value
  is out of range, to a jump to the no-label code. Otherwise each label
  is compared in turn, a range `lo..hi` by two compares, and the end of
  the chain jumps to the no-label code. That is `ELSE`'s body, or the
  trap with code 3. Every arm's body ends in a jump to the end.
- **`FOR`**: `AOBLEQ`/`ACBL` where the step and types fit, otherwise
  compare and branch. Done (step 4), compare and branch only: `ACBx` and
  `AOBLEQ` branch by a word or a byte, which a long body would not reach
  (§3), and Phase 18 can choose them. The start value is assigned, then
  the limit evaluated once, as `Oberon2.pdf` §9.8 says, and kept in a slot
  of the frame unless it is a constant (a variable too, which the body
  may change). The test is at the head, `v > limit` (`v < limit` for a
  negative step) leaving the loop; `v` is stepped at the foot by the
  type's own `ADD` (`INC`/`DEC` for 1 and -1), wrapping as all integer
  arithmetic does.
- **Arrays and records**: a field is its offset from the record's address;
  an index is checked (§9), then scaled, or used through index mode
  (`base[Rx]`), which scales by the element size itself. **Decided
  (2026-10-06): index mode for an element of 1, 2 or 4 bytes, else its
  address.** Done (step 6): a constant index is a displacement, checked
  by the compiler. Any other is widened to a longword in a register of its
  own and checked (§9); then an element of 1, 2 or 4 bytes is `base[Rx]`
  (`MOVW L_A[R2], R0`), and any other - a record, an array or a `HUGEINT`,
  whose second longword index mode cannot name - is scaled by `MULL2
  #size, Rx` and made an address by `MOVAB base[Rx], Rx`, its fields then
  `off(Rx)`. Index mode scales by the operand's size in the instruction,
  so an indexed element used where that size is another - `ASHL`'s count
  and `BBC`'s base are bytes, `BLBC`'s operand a longword - is moved to a
  register first, and an element's address is `MOVAW`/`MOVAL` for a word
  or a longword element. The registers of a location stay where they are
  while the rest of the statement is evaluated: never spilled, since a
  base or an index cannot be in the frame, but moved up from `R0` and
  `R1` before a call. A `CASE` selector or a `FOR` limit that holds one
  is copied to the frame. An assignment's target is located before its
  value is evaluated, as on LLVM.
- **`COPY`** and whole-array or whole-record assignment: `MOVC3`, whose
  length is a word (`MOVC3 len.rw, ...`, MACRO), so up to 65535 bytes; longer moves loop.
  Done (step 6) for assignment: `MOVC3 #size, src, dst` of the value's
  size (an array no longer than the target's, `language-extensions.md`,
  "Array assignment"), a longer move in pieces of 65535, each next one
  `MOVC3 #n, (R1), (R3)` from where the last left `R1` and `R3`; clearing
  more than 65535 bytes of locals is pieces of `MOVC5` the same way.
  **`COPY(x, v)`, done (step 7)**: `x`'s characters up to its first `0X`,
  at most `LEN(v) - 1` of them, then `0X` (`Oberon2.pdf` 10.3), the rest
  of `v` left as it was: one `MOVC5 #n, x, #0, #n+1, v`, the `n` bytes then
  one fill byte. A string constant's `n` is known; an array's is counted
  by `LOCC #0, #LEN(x), x`, which leaves in `R0` the bytes from the `0X`
  on, or 0 (MACRO 9-130), so `SUBL3 R0, #LEN(x), R0`, then limited to
  `LEN(v) - 1`, `R1` one more. `LOCC` and `MOVC5` overwrite `R0`-`R5`,
  so an address held in a register is moved to the frame first and used
  as `@n(FP)`. **Decided (2026-10-08): a longer `x` or `v` is done in
  pieces**, the lengths being words (step 7b): `m`, the most characters
  to copy, is `LEN(v) - 1` or `LEN(x)` if less; `LOCC #0` searches at most
  65535 bytes at a time from `R1`, `R2` the bytes left, until it finds the
  `0X` or `m` bytes are searched, and `R1` less `x`'s address is `n`,
  pushed on the stack; `MOVC3` moves at most 65535 at a time, each from
  where the last left `R1` and `R3`, the count left on the stack, as
  `MOVC3` overwrites `R0`-`R5`; then `CLRB (R3)`. A string constant of
  65535 characters or more is `CopyBytes`' pieces and `CLRB (R3)`.
- **The predeclared procedures of the slice (§1), done (step 7), and
  `INCL`, `EXCL`, `SHORT`, `LONG` and `ASH`, added to the slice with the
  user 2026-10-08 (step 7b), as they need no heap.** A call whose value is
  constant is folded (`LEN` of a fixed array among them); the others:
  - `ABS(x)`: `MOVx x, r` (which sets N), `BGEQ` over `MNEGx r, r`; `MNEG`
    of the most negative value is that value (MACRO 9-23), as wrapping
    arithmetic promises. A `HUGEINT` tests its high longword and is
    negated as `-x` is.
  - `ODD(x)`: `BICB3 #254, x, r`, the low bit of the low byte, read where
    it is (little-endian), an element in index mode first moved to a
    register.
  - `CHR(x)`: `CVTWB` or `CVTLB` (of a `HUGEINT`'s low longword), the low
    byte; with `-range-checks` a value outside 0..255 traps first (§9).
  - `ORD`: `MOVZBW` of a `CHAR`; `CVTLW`, the low word, of a `SET`.
  - `CAP(x)`: `SUBB2 #32` when `x` is 97 to 122, by unsigned compares.
  - `INC(v, n)` and `DEC(v, n)`: `v`'s own `INC`/`DEC`/`ADD2`/`SUB2` in
    place (`ADDL2`/`ADWC` for a `HUGEINT`), at `v`'s width: a narrower `n`
    sign-extended, a wider one's low bytes (`CVTxy`), a constant wrapped.
  - `HALT(n)`: `PUSHL #n` and `CALLS #1, G^POC_HALT`, poc's runtime
    routine, which ends the program with `n` as its status; it and what
    VMS sees are Phase 16's, as for `POC_TRAP` (§9; done, §14 item 10). **Decided with the
    user (2026-10-08): a routine, not `$EXIT_S` in line, so that Phase 16
    can run the modules' cleanup there first.**
  - `INCL(v, x)` and `EXCL(v, x)`: `BISL2` and `BICL2` of `x`'s mask on
    `v` in place, a constant's an immediate, any other's `ASHL x, #1`, as
    a constructor's element (`ASHL`'s count `x`'s low byte), so that an
    `x` outside 0..31 changes nothing.
  - `SHORT(x)`: `CVTLW` or `CVTWB`, or `MOVL` of a `HUGEINT`'s low
    longword; with `-range-checks` a value that does not fit traps first
    (§9). `LONG(x)`: `CVTBW` or `CVTWL`; of a `HUGEINT`, itself.
  - `ASH(x, n)`: `ASHL n, x, r`, or `ASHQ` for a `HUGEINT` `x`, in the
    wider of `LONGINT` and `x`'s type, which give 0, or the sign for a
    right shift, for a count of the width or more, as poc promises
    (`language-extensions.md`, "Procedure values, `ASH`, `MAX` and
    `MIN`"), for any count of -128..127. The count is a byte, so a
    `SHORTINT` `n` is used as it is and a wider one first limited to
    -64..64 (a constant when compiling).
  - `LEN` of an open array, and the predeclared procedures outside the
    slice (`ASSERT`, until its trap is settled (done, §14 item 11), `NEW`, `SIZE` of a
    variable size, `ENTIER`, the `SYSTEM` ones, ...), are reported. A predeclared procedure is taken to change only the
    variable it changes (the first argument of `NEW`, `INC`, `DEC`, `INCL`
    and `EXCL`, `COPY`'s second), so `ABS(x)` does not make a value
    parameter `x` be copied on entry.
- **Strings.** **Decided (2026-10-06): a string constant assigned to an
  array is `MOVC5`, its characters then zeros to the array's end**:
  `MOVC5 #len, L_STR_n, #0, #size, a`. A string constant is in
  `POC_CONST`, `L_STR_<n>:` and `.ASCII` between a delimiter it does not
  hold (MACRO 6, `.ASCII`), a character that does not print `.BYTE`, then
  its `0X` and any padding by `.BYTE 0[n]`; one for each text and size.
  **Decided (2026-10-06): a comparison of strings is a call of the
  runtime routine `POC_STRCMP(a, LEN(a), b, LEN(b))`**, by `CALLG`, the
  addresses and the lengths (a string constant's counting its `0X`) by
  value, its result in `R0` less than, equal to or greater than zero, as
  `a` is less than, equal to or greater than `b`, then `TSTL R0` and the
  relation's branch. Phase 16 writes the routine, which stops at `0X` or
  a length; `CMPC3` alone would not stop at `0X`.

## 9. Traps

Facts: the VAX has an `INDEX` instruction that checks a subscript range and
traps, its condition being `SS$_SUBRNG` (MACRO, `INDEX`, and its table
of exceptions), and integer division by zero traps in hardware
(§8).

Proposal: every check the LLVM backend makes (index range, `CASE` without
a label, `CHR` range, `SHORT` range, `ASSERT`, `HALT`, a function's missing
`RETURN`, ...) compares and branches to a call of one runtime routine with
the trap's code and the source position, so the report is the same as on
LLVM. Phase 15 writes the call; the routine, and what VMS sees (a signaled
condition or an exit status), are Phase 16 step 3c's. `INDEX` is not used:
its trap is a VMS condition (`SS$_SUBRNG`), not poc's message.

**Decided (2026-10-06): the call is `POC_TRAP(code, module, line,
column)`**, by `CALLS`, the arguments by value except the module's name:

    PUSHL   #<column>
    PUSHL   #<line>
    PUSHAB  L_MODULE_NAME
    PUSHL   #<code>
    CALLS   #4, G^POC_TRAP

The code is the LLVM backend's exit status for the trap (index 2,
`CASE` 3, NIL 4, guard 5, `WITH` 6, length 7, `ENTIER` 8, array
assignment 9, `ASSERT` 10, heap 11, `RETURN` 12, record assignment 13,
range 14), and the module's name is a counted string, `L_MODULE_NAME:
.ASCIC /<Module>/` in `POC_CONST`. A module that traps declares
`.EXTERNAL POC_TRAP`; until Phase 16 provides the routine, its object
assembles but does not link. Done (step 4) for `CASE`; done (step 6)
for an index, `CMPL Rx, #<length-1>` and `BLEQU` over the trap, unsigned
so that a negative index fails too, at the index's line and column (a
`HUGEINT` index also fails when its high longword is not zero); done
(step 7) for `CHR` under `-range-checks`, code 14 at `CHR`'s position:
`TSTB` for a `SHORTINT`, an unsigned compare with 255 for a wider integer,
and for a `HUGEINT` its high longword not zero too; done (step 7b) for
`SHORT` under `-range-checks`, code 14 at `SHORT`'s position: `BVC` over
the trap after `CVTLW` or `CVTWB`, which set V when the value does not fit
(MACRO 9-16), and for a `HUGEINT` its high longword not its low one's
sign; the others come with their constructs. Done (step 3, §14 item
10): the routine, `POC_TRAP` in `rtl/vax/PocRtl.mar`, which writes LLVM's
message to `SYS$ERROR` and exits with item 10's status, and the two more
arguments `-trap-location` adds.

## 10. Output and fixtures

- **Decided (2026-10-06): both `-emit-macro32` and `-target
  vax-dec-vms`.** `-emit-macro32 <file>` writes `<Module>.mar` where
  `-emit-llvm-ir` writes `.ll`, and implies the target; `-target
  vax-dec-vms` names it, and with another command that needs assembling
  or linking (`-build`, `-compile`, `-library`, `-install-library`) is an
  error until Phase 16, as `-emit-llvm-ir` is always (LLVM has no VAX).
  `-check`, `-emit-interface` and `-show-interface` take it, folding for
  the VAX's 32-bit word; the VAX takes only `-O2` (§4). DCL uppercases whatever on its
  command line is not quoted (the user, 2026-10-05), so poc on VMS sees
  `-EMIT-MACRO32`. **Decided (2026-10-05): poc's options stay lowercase,
  and poc on VMS matches every option without regard to case** - all of
  them, `-build` and `-o` as much as the new ones. That is Phase 16's to
  build, since poc first runs on VMS there (`PLAN.md` Phase 16 step 4);
  option *values* that are names (modules, files) are not covered, and
  stay that step's question.
- Fixtures: `test/conformance/vax-*/` each with a `.mod`, its
  `expected-vax.mar` and, at the top of that file, a comment by the
  reviewer saying why the output is right, in lines starting `;;`. The
  harness diffs the output against it without those lines
  (`test/vaxfixture.sh`, `vax_mar`). `test/testenv.sh` deletes a fixture's
  `*.mar` before each run, except `expected-vax.mar`.
- Since Phase 18 step 3e (2026-10-18) each fixture with an
  `expected-vax.mar` also has an `expected-vax.image`, and each import an
  `expected-vax-<Import>.image`: the image of the object MACRO made from
  that `.mar` on the guest (`tools/vax-macro-image`), which `vax_mar`
  compares with the image poc's encoder makes (`poc -emit-vax-image`), on
  every host (`vax-object-language.md`, section 14.5). When an expected
  `.mar` changes, its image is made again from MACRO, never from poc.
- **Decided: every `expected-vax.mar` is also assembled**, with
  `MACRO/OBJECT` on the development system - no `LINK`, no `RUN` - so the
  assembler, not only a reviewer, checks the syntax, the symbols and every
  branch's reach. This changes `PLAN.md`'s locked-in "no assembling" for
  Phase 15; linking and running stay Phase 16's, except the debugger runs
  below. `tools/vax-assemble`
  does it (§11, question 2: scripted telnet), and `vax_mar` runs it on
  `expected-vax.mar` where `tools/vax-assemble -available` says the guest
  can be used; elsewhere that part is skipped, so the fixture's result is
  the same on every host. It is skipped too in the suite runs after
  `make test`'s (`VAX_GUEST=skip`; `DEVELOPER.md`, section 4), since the
  guest sees the same file in each. A file that does not assemble adds MACRO's
  messages to the result, which then fails.
- **Decided (2026-10-06): a fixture may also run its `expected-vax.mar`
  under the VAX debugger**, where the guest can be used, as it is
  assembled: `tools/vax-run` links it with stand-ins for poc's runtime
  routines (`tools/vax-runtime-stub.mar`; `POC_TRAP` keeps what it was
  given in `POC_TRAP_CODE` (the code's low word), `_LINE`, `_COLUMN` and
  `_MODULE` and ends the program, `POC_HALT` its code in `POC_HALT_CODE`; `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and `POC_HMOD` compute what
  the real ones will), the main module first, so the image starts at its
  `<MODULE>_MAIN` (§6; until step 8 a driver called `<MODULE>_INIT`), and
  runs it once for each `run-<name>.dbg`, its output compared with
  `run-<name>.log` (`DEVELOPER.md`, section 4). A fixture of several
  modules (step 8, `vax-modules`) has an `expected-vax-<Import>.mar` for
  each import, compared with what poc writes for it and assembled and
  linked with `expected-vax.mar`. This checks what the code does, which
  assembling cannot; the step 6 fixtures were the first, then those of
  steps 3-5 with code to run, then step 7's. Linking and running poc's own runtime and
  programs stay Phase 16's.
- `VaxToolchainDriver.Mod` was a stub that wrote the `.mar` and reported
  that assembling was not available (`PLAN.md` Phase 15); Phase 16 step 2
  gave it `-build` and `-compile` (§13). As for IR, the `.mar` of every
  module compiled from source is written, or none, when `VaxCodeGenerator`
  reports what it cannot lower yet.

## 11. Open questions

Settled 2026-10-05: the development system (§2); assembling fixtures in
Phase 15 (§10); one calling mechanism (§7); `-O2` only and
`MemoryLayout`'s record layout (§4); the stem-and-hash names (§5);
options matched without regard to case on VMS (§10). Settled
2026-10-06: collisions across a link (§5.1), and with it the hash (§5);
running `MACRO` on the guest, by scripted telnet (question 2); integer
arithmetic at the type's width (question 4); the trap call (§9). Settled
2026-10-08: the module key's and the name scheme's symbol (question 8)
and the program's start (§6).

1. **The destination machine's version** - the user is to check it.
2. **Running `MACRO` on the guest from the host**, for assembling
   fixtures: settled 2026-10-06, **scripted telnet**. Copying was settled
   2026-10-05: FTP to `192.168.2.20` as `poc`, active mode, ASCII, the
   password in `~/.netrc-poc-vax` (`~/.netrc` until 2026-10-08;
   `doc/developer/DEVELOPER.md` section 4). A host-side command logs in by
   telnet as `POC`, the password read from that file and never echoed, logged or printed, runs
   `MACRO/OBJECT/LIST` in `POC`'s own directory, reports the assembler's
   `$STATUS`, and the `.LIS` comes back by FTP. It works unattended, since
   the fixtures run from `make test`; on a host without the guest those
   checks are skipped, as `doc-poc-man-page` is without mandoc. Checked
   first: the guest runs DEC TCP/IP Services for OpenVMS VAX (UCX) 3.1,
   whose `UCX SHOW SERVICE` lists only FTP and TELNET, so no `rexec` or
   `rsh` (ports 512-514 closed); whether 3.1 has those servers at all,
   not configured, was not checked. A batch job on the guest watching a
   directory was the other choice, kept in reserve.
3. **The hash (§5)**: settled 2026-10-06 with §5.1 - 40 bits of FNV-1a
   in base 32, kept; collisions are caught, not made rarer.
4. **Integer arithmetic on `SHORTINT` and `INTEGER` (§8)**: settled
   2026-10-06, **at the type's width**.
5. **Packed records** for VMS routines (§4) - Phase 17's, noted here.
6. **`LONGREAL`'s default format (§4)**, D_floating as VAX C, or
   G_floating - Phase 16's, noted here so the option is designed in.
   Settled 2026-10-09: G_floating (§14, item 9).
7. **Collisions across a link (§5.1)**: settled 2026-10-06. Still to be
   checked on the development system: whether the Librarian reports
   `DUPGLOBAL`.
8. **The module key's and the name scheme's symbols (§5.1)**: the VAX
   spellings of LLVM's `<M>.-key.…` and `<M>.-target.…`, unhashed, at most
   31 characters, and never equal to a hashed symbol or `<MODULE>_INIT`.
   Settled 2026-10-08: **one symbol, `POC_K1_<KEY>`**, the scheme's
   version in its name (§5.1).

## 12. Proposed order of work

Each step lands with its fixtures before the next, as Phase 8 did:

1. `VaxTypes.Mod`: sizes, offsets and the name scheme (§4, §5), with the
   name fixtures - long names, names differing only in case, module names
   with a common start, and the colliding pair of §5.1, which poc must
   reject within one module. Done.
2. The driver option and the stub `VaxToolchainDriver.Mod`; an empty
   module's `.mar` (§6). The host-side command that copies a `.mar` to the
   development system, runs `MACRO/OBJECT` and brings the result back
   (§11, question 2), with a hand-written `.mar` first, then the empty
   module's. Done.
3. Straight-line code: module variables, assignment, integer, `CHAR`,
   `BOOLEAN` and `SET` expressions. Done.
4. Control flow (§3 branches, §8), with the trap call (§9). Done.
5. Procedures and calls (§7), then external `["VMS"]` procedures. Done.
6. Arrays and records, with the traps (§9). Done.
7. The predeclared procedures of the slice. Done.
   7b. `INCL`, `EXCL`, `SHORT`, `LONG` and `ASH`, and `COPY` of more than
   65535 characters (decided with the user 2026-10-08). Done.
8. Several modules and the program's start (§6). Done.
9. The phase record and the exit review.

## 13. Building a program (Phase 16 step 2)

**Decided (the user, 2026-10-09)**: on the Linux or BSD host, poc writes
what VMS needs and runs nothing there. `poc -target vax-dec-vms -build
<file>` (or `-target vax-dec-vms <file>`) writes every module's `.mar`
in the output directory and a DCL procedure at `-o`'s path with `.com`
for its `.exe`, by default `<Main>.com` in the current directory, as
the executable is named for LLVM. The procedure assembles each module
(`MACRO/OBJECT`, the imports first), writes a linker options file
`<IMAGE>.OPT` listing the objects, the main module's first, and links
`<IMAGE>.EXE` from it and poc's runtime. `-o`'s last component, without
`.exe` in any case, must be an ODS-2 name: 1 to 39 letters, digits,
`_`, `$` and `-`. `poc -target vax-dec-vms -compile <file>...` writes the
named modules' `.mar`, with no program's start, and
`<outputDir>/<First>.com`, which only assembles them. Both are silent on
success. Every module of a `-build` must be compiled from source, since
VMS libraries are Phase 17's.

- **The options file** keeps the `LINK` command short. DCL limits a
  command's length, and poc's own program has over forty modules. The
  procedure writes it with `CREATE`, from the lines that follow, so the
  procedure stays one file.
- **A warning stops the build.** `ON WARNING THEN EXIT $STATUS` comes
  first, so a `MACRO` warning, or `%LINK-W-MULDEF` (§5.1, layer 1), ends
  the procedure with that step's status. Otherwise it exits with the
  `LINK`'s.
- **poc's runtime** is one object, `POCRTL.OBJ`, assembled from
  `rtl/vax/PocRtl.mar`. The procedure takes it from `POC$RTL:` when that
  logical name is defined, otherwise from the current directory. It is
  linked as an object, not taken from a library, so it is always in the
  image. At step 2 it has `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and
  `POC_HMOD`, the same code as `tools/vax-runtime-stub.mar`'s, which
  stays as it is for the debugger runs. `POC_TRAP` and `POC_HALT` are
  provisional: they end the program with `SS$_ABORT` and `SS$_NORMAL`
  until step 3c decides what a trap reports and what DCL sees of
  `HALT(n)`. (Done: §14, item 10.)
- **What is checked.** `test/conformance/vax-hello` assembles, links and
  runs a hand-written program, `hand-hello.mar`. `vax-build` compares the
  procedures with `expected-<name>.com`, then runs them on the guest
  (`test/vaxfixture.sh`, `vax_do`) and runs the program. Until the
  runtime has `Out`, the program shows what it computed in its exit
  status, which DCL's `$STATUS` shows. The `.mar` files poc writes there
  are not compared: the run checks them.
- **`-link <line>`** (the user, 2026-10-27; `PLAN.md`, "Ongoing
  implementation enhancements", item 9): each argument is a line of
  `<IMAGE>.OPT`, after the libraries' lines and before the runtime's, as
  `-link`'s arguments follow the libraries in clang's command. Before it,
  a program could link nothing poc had not compiled (section 23.2). A
  library built with `-link` (section 18) has the lines in its shareable
  image's options file, before its `UNIVERSAL=` lines, and its manifest
  records them as `link <line>`, as on LLVM: a program that links the
  library, its `.OLB` or its `.EXE`, gets them before its own, each line
  once (`Poc.VaxOptionLines`, after `LLVMBackEnd.PrepareLibraries`).
  An image linked against the library's `.EXE` does not need them, but
  they are harmless there, and one rule for both keeps it simple. poc
  checks no line's syntax, which the Linker does, but refuses two that
  would break the procedure, found on the development system
  (2026-10-27): one starting with `$`, which ends `CREATE`'s data (only
  a `$` in column 1 does), and one over 512 characters, the longest data
  line `CREATE` reads (513 gives `%CREATE-E-READERR`, `RMS-W-RTB`; LINK
  takes 512). A line in a library's manifest is checked when a program
  uses it. The Linker manual (`AA-LA62A`, section 3.2) has the rest: one
  option a line, `-` continuing it, `!` a comment, and no `/OPTIONS`
  inside an options file, so no including one. A line naming a psect
  no object has, `PSECT_ATTR=NO_SUCH_PSECT,NOSHR`, links with no
  warning, so a library may record one for every program. Fixture
  `vax-link` builds a program whose externals only the lines resolve,
  an object library's routine and a shareable image's, and runs it on
  the guest.

### 13.1 Object files on the command line (proposed 2026-10-27)

`PLAN.md`, "Ongoing implementation enhancements", item 9. Proposals 1-4
and 7, what an object is, which commands take one and what LLVM does
with it, are in `llvm-toolchain.md`, "Object files on the command line";
these are the VAX's. An object is a `.obj` in any case among `-build`'s
or `-library`'s files (proposal 1), and its name without `.obj` must be
a VMS file name (1 to 39 letters, digits, `_`, `$` and `-`) and not a
module's, a command table's or another object's, as for a `.cld` or a
library's `.mar` part (`Poc.AddVaxPart`). `-link` already reaches an
object that is on VMS by its file specification (`-link
DISK:[DIR]FOO.OBJ`); these are for one poc copies, so the procedure is
whole in one directory, as with the modules' own.

5. *`-build`.* Each object is copied beside the modules' `.mar` or
   `.obj`, as a `.cld` is, and listed in `<IMAGE>.OPT` after the modules
   and the command tables, before the libraries and `-link`'s lines. On
   VMS the copy keeps the records whole (`ObjectRecords.Copy`, as a
   library's objects are installed). On Linux or a BSD poc copies the
   bytes, and the file must be in the counted form poc's own objects
   have there (a 2-byte count, the record, a pad byte after an odd one:
   `vax-object-language.md`, section 15.3), so that the procedure's
   `OBJCONVERT` step converts it as it does those, when it arrives as
   fixed 512-byte records; the procedure converts a foreign object
   whether the modules are objects or MACRO-32 (`-vax-macro32`).
   *Done 2026-10-27* (fixture `vax-build-object-files`), but for the
   check on VMS, which takes any file there until the reader of records
   below exists (`ObjectRecords.IsCounted`, the host's a walk of the
   counts). An object may not be named `POCRTL` either, the runtime's
   object in the current directory when `POC$RTL` is not defined. Every
   other command but `-library` (proposal 6), and any other target,
   refuses a `.obj` ("a VAX object file (.obj) is linked only by -build
   or -library for vax-dec-vms"). A name VMS cannot have is reported with the
   file's own extension now, `.mar`, `.cld` or `.obj`.
6. *`-library`.* The same copy and names. Each object is inserted in
   `<NAME>.OLB` and listed in the shareable image's options file after
   the modules and the `.mar` parts, its global entry points made
   `UNIVERSAL=` as a part's `.ENTRY` routines are, and the manifest
   gets an `object <name>` line (`part <name>`'s twin), so that
   `-install-library` copies it. The entry points come from the object's
   GSD records: the entry point definitions, `GSD$C_EPM` (2) and
   `GSD$C_EPMW` (5), and the procedures with formal arguments, `GSD$C_PRO`
   (3) and `GSD$C_PROW` (6) (`AA-LA62A`, section 7.3), the first as
   `tools/vax-image/ObjectImage.Mod` reads them, by a
   small reader of records: `ObjectRecords.Open` and `Get` in both
   versions, the host's of the counted form, VMS's over a new
   `RecordFiles.Open` and `Get` (`POC_RECORD_OPEN` and `POC_RECORD_GET`
   in `PocRtl.mar`, `$GET` in record mode). VMS's `Files` cannot read
   them: it reads a variable-length file a record at a time with an LF
   after each, and an object's records hold LF bytes.
   *Done 2026-10-27* (fixture `vax-library-object-files`, run on the
   guest). Every GSD subrecord of the object language's types 0 to 12
   is parsed in full, since none has a length field, and the local ones,
   `LEPM` (10) and `LPRO` (11), are not made universal; a subrecord of
   another type, or one that runs past its record, is refused ("cannot
   read the global symbols of"), as are the names `-build` refuses, all
   before the library's directory is made. The manifest's line is
   `object <name>.obj`, the file's name, as LLVM's records `twice.o`;
   `-install-library` deletes an older copy's objects before it copies
   the new ones.

Proposal 7's fixtures for the VAX: `-build`'s and `-library`'s
procedures and the manifest compared, and the refusals, on every host;
on the guest, a hand-written `.MAR` assembled there into the object a
program and a library link, and the program run.

**Open questions, settled.** (a) *Answered on the guest, 2026-10-27:* a VMS
object fetched by FTP in binary mode (`TYPE I`) arrives as its records
run together with no counts and no pad bytes (a 13-record `FTPCHK.OBJ`
of 253 bytes, `MACRO/OBJECT` of a one-routine `.MAR`, fetched with
curl), so its record boundaries are lost, as `vax-object-language.md`,
section 17 found for `test-vax-guest-poc`. Proposal 5 therefore takes,
on Linux or a BSD, only an object in the counted form (one poc wrote,
or one another host tool wrote in it), and poc checks it before copying:
its counts must walk exactly to the end of the file, none above 512
(the object language's longest record, and the most OBJCONVERT takes),
each record's first byte a record type (`OBJ$C_HDR` .. `OBJ$C_EOMW`,
0..7), else poc refuses it ("<file> is not a VAX object in the counted
form"). An object made on VMS is named there instead: by poc running
on VMS, which copies it with `ObjectRecords.Copy`, or by its file
specification with `-link` from any host. (b) *Decided (the user, 2026-10-27): a library reads
an object's global symbols* (proposal 6), so that an object behaves as
a `.mar` part, its entry points universal, rather than usable only from
inside the library.

### 13.2 An object from VMS in the counted form (proposed and approved 2026-10-27)

`PLAN.md`, item 9, the step after proposal 5 (the user, 2026-10-27).
Proposal 5 takes on Unix only an object in the counted form, and FTP in
binary loses an object's record boundaries on the way from VMS (13.1,
question (a)), so an object made on VMS by MACRO, a compiler or the
Librarian cannot reach a link poc writes on Unix except by `-link` and
its VMS file specification. This is the reverse of `OBJCONVERT`: a
program on VMS writes an object's records in the counted form into a
file whose bytes FTP in binary carries as they are.

1. *`RecordFiles.Open` and `Get`.* `Open(name): File` opens a file of
   records to be read, NIL if it cannot be opened or is not one;
   `Get(f, VAR bytes, VAR length): BOOLEAN` reads the next record into
   `bytes` and its length into `length`, FALSE at the end of the file.
   A record longer than `bytes`, one that cannot be read, or a `Get` on
   a file made by `Create` or closed stops the program with a message
   naming the file and HALT(99), as `Put` does. They need no new
   MACRO-32: `PocRtl.mar`'s `POC_FILE_OPEN` already opens a
   variable-length file to be read a record at a time (and Stream_LF,
   fixed-length and undefined ones by block I/O, which `Open` closes
   again and refuses), sharing it as `Files` does, and `POC_FILE_GET` is
   `$GET` into a buffer. This replaces 13.1 proposal 6's
   `POC_RECORD_OPEN` and `POC_RECORD_GET`, and proposal 6's VMS
   `ObjectRecords.Open` and `Get` will be built on these.
2. *`RecordFiles.CreateFixed`.* `CreateFixed(name, size): File` makes a
   sequential file of fixed-length records of `size` bytes (1 to
   32,765), no record attributes, written by `Put`, each record exactly
   `size` bytes (any other length stops it, as a length outside 0 to
   maximum does now). One new entry in `PocRtl.mar`,
   `POC_RECORD_CREATE_FIXED`, `POC_RECORD_CREATE` with `RFM=FIX` and
   `MRS=size`, sharing its code. It is what FTP in binary sends byte for
   byte, as poc's objects arrive on VMS as such a file: a Stream_LF file
   made by `Files` is not safe, since a transfer that reads it by records
   drops its LFs.
3. *`OBJCONVERT -COUNTED <object> <counted file>`.* The same program and
   image as now, with a first argument (in any case, as DCL makes it
   uppercase) that turns it round, so the kit builds, installs and keys
   nothing new and `SETUP.COM`'s command does both. It reads each record
   of `<object>` with `RecordFiles.Get` (a buffer of 512 bytes, the
   object language's longest record), writes its count, low byte first,
   its bytes and a pad byte after an odd count into 512-byte records of
   a `CreateFixed` file, and pads the last with zeros. A record that does
   not fit, an empty record, or an `<object>` that is not a file of
   records (one sent from Unix and not converted yet) stops it with a
   message and HALT(2), the file it began deleted, as now. It prints
   nothing when it succeeds. The usage message names both forms.
   Not checked: that the records are an object's; poc checks that on
   Unix (proposal 4), the Linker on VMS.
4. *The end of a counted file.* The zeros after the last record (2 to
   511 bytes, the counts and pads keeping every record even) end a
   counted file, as `OBJCONVERT` stops at a count of 0: `ObjectRecords.
   IsCounted` (the host's) takes a count of 0 followed only by zero bytes
   as the end, where it now refuses it; poc's own objects have no such
   end and are unchanged. So the file `-COUNTED` writes, fetched in
   binary, goes straight to `-build` (proposal 5) and back to VMS through
   `OBJCONVERT`.
5. *Documents.* `vax-vms-guide.md` chapter 3, "Linking other objects and
   libraries": how an object made on VMS reaches a link poc writes on
   Unix (`$ OBJCONVERT -COUNTED TWICE.OBJ TWICE.CNT`, FTP's `binary` and
   `get`, the file renamed `twice.obj`); the `OBJCONVERT` sentences there
   and in chapter 2, `README.TXT` and `SETUP.COM`'s comment name both
   directions; `RecordFiles`' comment and the guide's runtime list gain
   `Open`, `Get` and `CreateFixed`, and `rtl/vax/README.md` its line.
6. *Fixtures.* On every host: `IsCounted`'s new end in
   `vax-build-object-files` (a counted object padded with zeros taken,
   one with a nonzero byte after its count of 0 refused). On the guest,
   one new fixture, `vax-objconvert-counted`: a hand-written `.MAR`
   assembled there by `MACRO/OBJECT` (an object poc did not write),
   `OBJCONVERT -COUNTED` of it, `OBJCONVERT` of that back, and the two
   objects' `DUMP/RECORDS` compared; the counted file fetched in binary
   and given to `poc -target vax-dec-vms -build` on the host, its
   records (`tools/vax-objects.sh`'s `counted_records`) compared with
   the original's `DUMP/RECORDS` (`dumped_records`); and the refusals:
   an object not a file of records, a missing one, too few arguments.
   `RecordFiles.Open` and `Get` get a guest program of their own in the
   same fixture: records of 0, 1 and 512 bytes read back, a record
   longer than the buffer, a Stream_LF file refused, a missing file NIL.

**Approved by the user, 2026-10-27**, all six as written. *Done
2026-10-27*, with these differences:

- Proposal 1 did need MACRO-32 after all: `POC_FILE_GET` returned the
  same -2 for every failure, so it now returns -3 on `RMS$_RTB`, a
  record longer than the buffer, and `Get` names that ("record longer
  than the space for it") apart from one that cannot be read. `Files`
  and `Platform` take -3 as they took -2. `Put` on a file `Open` opened
  stops the program too.
- Proposal 3's buffer is 32,765 bytes, the longest record `Get` can
  read, not 512, so that an object's record longer than 512 bytes gets
  `OBJCONVERT`'s own message ("a record longer than 512 bytes") and
  HALT(2) rather than `RecordFiles`' HALT(99). `OBJCONVERT -COUNTED
  <object>` alone, three arguments with the option first, gets the
  usage message rather than being taken as a counted file called
  `-COUNTED`.
- Proposal 4's end is also `tools/vax-objects.sh`'s: `counted_records`
  stops at a count of 0.
- For proposal 6, `tools/vax-do -get` brings a `<NAME>.CNT` back in
  binary (`ftp_get_binary` in `tools/vax-ftp.tcl`) and every other file
  in ASCII as before. `vax-objconvert-counted` also refuses an object
  with an empty record and one with a 630-byte record, each leaving no
  file, and its counted output is named `REFUSED.CNT`: `tools/vax-do`
  sends `Out`'s object, which the guest program imports, as `OUT.CNT`.

### 13.3 Options files on the command line (proposal 9, approved 2026-10-28)

`PLAN.md`, item 9. A `.opt` in any case among the files of `-build` or
`-library` for vax-dec-vms is an options file for the Linker, and its
lines are `-link`'s (the user, 2026-10-28: "recorded like -link"). poc
reads the file, so it is on the machine where poc runs, and the
procedure poc writes holds its lines, not its name, so nothing more is
sent to VMS.

- *Its lines.* Each is taken as `-link`'s argument is, after the
  `-link` arguments, in the order of the files and their lines: the
  blanks and tabs around a line dropped, and a CR before its LF; a
  blank line, and a comment, one that starts with `!`, left out; and a
  line that ends in `-`, the Linker's continuation (`AA-LA62A`, section
  3.2), joined with the next without the `-`, so that the line is one
  in the options file too, where a line seen twice is linked once (13,
  "`-link`"). A comment at the end of a line is the Linker's and stays.
  An options file cannot name another (`/OPTIONS` is not allowed in
  one), so poc reads none further.
- *In `-build`.* The lines go into `<IMAGE>.OPT` after the libraries'
  recorded lines and the `-link` arguments, as one more `-link`
  argument would.
- *In `-library`.* The same lines go into the shareable image's link and
  into the manifest as `link <line>` lines with the `-link` arguments,
  so that every program linked with the library, against its `.OLB` or
  its `.EXE`, gets them. The guest showed (2026-10-28, `PSECT_ATTR=
  COMMON_A,NOSHR` for a library that has the `COMMON_A` psect) that such
  a line in a program's link does no harm where the program does not
  need it: no warning against the `.EXE`, nor with the library's object
  linked in, and against the `.EXE` a program with its own `COMMON_A`
  that gets `%LINK-W-MULPSC` without the line links cleanly with it.
- *Refused*, each before anything is written: a `.opt` that cannot be
  opened; an option that starts with `$`, which would end `$ CREATE`'s
  data in the procedure, or is longer than 512 characters once joined
  (`VaxToolchainDriver.optionLineLength`), either named by the file and
  the line it starts on (`Seven.opt, line 4:`); a continuation past the
  end of the file; and a `.opt` given to any other command or target ("an
  options file (.opt) is linked only by -build or -library for
  vax-dec-vms").

*Done 2026-10-28* (`Poc.AddVaxOptionFile`; fixture `vax-options-files`,
run on the guest): `Seven.opt`'s `SYMBOL=SEVEN_VALUE,7`, continued over
two lines, defines the absolute symbol a program prints as the address
of an external procedure (`SYSTEM.VAL(SYSTEM.ADDRESS, E)`), built with
it by `-build`, and against the library SEVEN made with it, through
SEVEN's `.EXE` and its `.OLB`.

## 14. Widening the backend to poc's own source (Phase 16 step 3)

**Decided (the user, 2026-10-09): the VAX takes `-OC` as well as
`-O2`.** poc's own source is compiled under `-OC`, because
`Types.Value.intVal` and other values need a 64-bit `LONGINT`
(`tools/bootstrap/stage1`). It can't use `HUGEINT` instead, since
`check-strict` keeps it to Oberon2.pdf. Under `-OC` a `LONGINT` is a
quadword, lowered as a `HUGEINT` already is (§4). `INTEGER` is a longword
and `SHORTINT` a word. `-O2` stays the default. `VaxTypes.sizeModel` is
the driver's choice, and `VaxTypes.Longword` names the 4-byte integer
type that registers, indexes and the halves of a quadword use. The 32
reviewed `expected-vax.mar` files are unchanged by it.

**The survey.** Given to `-OC -emit-macro32`, poc's own source (`src/`,
without `rtl/llvm`, which step 4 replaces) has 22,504 constructs the
backend refuses:

| Area | Refusals |
|---|---|
| pointers, `NIL`, `NEW`, `IS`, type guards, `WITH` | 13,606 |
| records holding pointers, and `VAR` record parameters (`Files.Rider`, `Parser.Parser`, `LLVMCodeGenerator.Codegen`, ...) | 4,506 |
| open arrays: parameters, `LEN`, `COPY` to and from them | 4,340 |
| `REAL` and `LONGREAL` | 139 |
| procedure values and calls of procedure variables | 55 |
| nested procedures | 5 |
| `ASSERT`, `SYSTEM.SET64` | 2 |

The `["C"]` externals and `SYSTEM`'s `ADR`, `VAL`, `GET` and `PUT` are
only in `rtl/llvm`, so they are step 4's, in the VAX runtime.

**Decided (the user, 2026-10-09), as proposed**, each following the LLVM
backend's representation wherever the VAX allows it, so that the front
end's information serves both:

1. **Open arrays first.** They are needed before a shared fixture can
   print anything, since `Out.String` takes an `ARRAY OF CHAR`. An
   open-array parameter is its address followed by one hidden longword per
   open dimension, its length, as on LLVM: parameter *i*'s address at
   `4n(AP)`, its lengths in the next longwords. `LEN` reads them, and an
   index is checked against them (trap 2). `COPY` to or from one is a
   `MOVC3`/`MOVC5` of the shorter length, as step 7 does for fixed arrays.
   A value open-array parameter is copied to the stack on entry, by
   subtracting its size from `SP` at run time, as LLVM's `alloca` of a
   dynamic size does.
2. **Then a minimal `Out`, pulled forward from step 4**, so that step 3's
   fixtures can be what `PLAN.md` asks: the same `.mod` and the same
   `expected` output on both backends. `rtl/vax/Out.Mod` in Oberon-2 over
   one MACRO-32 routine in `PocRtl.mar` that writes a line with
   `LIB$PUT_OUTPUT`. `Out` buffers until `Ln`, since `LIB$PUT_OUTPUT`
   writes whole records. Until then, step 3's first fixtures show their
   results in the exit status or under the debugger, as Phase 15's did.
3. **Pointers and the heap.** A pointer is a longword address of the
   block's data, `NIL` 0, and the block's tag longword is at `-4` (a
   record's type descriptor; an open array's block holds its lengths
   there, as on LLVM). Each dereference is checked for `NIL` (trap 4) by
   `TSTL`/`BNEQ`. VMS leaves page 0 unmapped, so an unchecked one would
   fault `ACCVIO`, but the trap must be poc's, with its message. `NEW`
   calls a runtime routine, `POC_NEW(size, tag)`. **Until step 4 ports
   the collector**, it takes memory from `LIB$GET_VM` and never frees
   any, so programs that allocate a lot will run out. That is enough for
   step 3's fixtures, not for poc itself (step 6). (Since step 4, `NEW`
   calls the collector's `Allocate` with the same arguments: section
   15, "Done: the collector".)
4. **Type descriptors: LLVM's layout**, as one block per record type in
   `POC_CONST`, every field a longword: `ProcTab` below the tag, growing
   down; then `size`, `extLevel`, `ptrCount`, `BaseTypes[extLevel+1]` and
   `ptrOffsets[ptrCount]`. `IS` and a type guard are `extLevel >= T.level
   & BaseTypes[T.level] = T's tag`. The collector (step 4) reads
   `ptrOffsets`. Each descriptor's symbol is made from `<Module>.<Type>`
   by §5's scheme, and an exported type's is global, so importers can
   test against it.
5. **`VAR` record parameters** take the actual's tag as a second
   longword, as decided in §7. A record value parameter needs no tag.
6. **Type-bound procedures** are ordinary procedures, the receiver
   first. A call is direct when the receiver's type is known exactly,
   otherwise `CALLG list, @-4*(i+1)(Rtag)`, through the descriptor's
   `ProcTab`.
7. **Procedure values** are the longword address of the procedure's
   entry mask, which `CALLS` and `CALLG` take. Oberon-2 allows only
   global procedures as values, so no bound procedure values, and no
   environment, are needed.
8. **Nested procedures: lambda lifting by reference, as on LLVM**
   (`nested-procedures.md` §3). Each enclosing variable a nested
   procedure uses is passed as a hidden address argument after its own,
   using `NestedProcedures.Mod`'s analysis unchanged. A static link in
   `R1` (§7's earlier suggestion) would need a second mechanism, and poc
   has only 5 nested procedures.
9. **Reals (3a): `REAL` is F_floating; `LONGREAL` is G_floating by
   default**, not D_floating as VAX C's default is. poc itself needs G:
   `ConstantEvaluator.MaxLongReal` computes 2^1024 - 2^971 as a
   `LONGREAL`, and D_floating's largest value is about 1.7 * 10^38, so
   poc built with D would overflow folding `MAX(LONGREAL)`. G_floating has
   IEEE double's 53-bit precision and nearly its range (about 0.56 *
   10^-308 to 0.9 * 10^308), so poc's own folding gives the same values
   as on the hosts, except at the extremes. The KA655's CVAX does F, D
   and G in hardware. A `-vax-d-float` option can come later (§4 wanted
   the choice designed in). The VAX formats have no infinities, NaNs or
   denormals: a real overflow or division by zero is a hardware
   condition (`SS$_FLTOVF_F`, `SS$_FLTDIV_F`), as integer division by
   zero already is. This is a target difference, recorded where the x86
   and ARM one is (`AGENTS.md`, "What traps, and what does not"). A
   constant is written as decimal text that MACRO converts, never by
   converting IEEE bits (below, "Done: reals"). The VAX rounds a halfway
   case away from zero, not to even as IEEE does: it rounds by adding 1
   to the bit below the last one kept (MACRO 9.2.8.3), and MACRO V5.4-3
   on the guest converts a decimal literal the same way. So a folded
   value and a computed one can differ in the last bit. Fixtures avoid
   such cases or print them only on the VAX (`vax-reals`).
10. **Traps and exit status (3c).** `POC_TRAP` writes the same message
    the LLVM runtime does, with `-trap-location`'s position when that was
    given, to `SYS$ERROR`, then exits. A VMS exit status is a condition
    value, which DCL reports unless bit 28 (`STS$M_INHIB_MSG`) is set. So
    a trap with code *c* exits with `%X10000000 + 8*c + 2`: severity
    error, message number *c*, and DCL's own message suppressed, since
    poc's says what happened. `HALT(0)` exits with `SS$_NORMAL` (1), and
    `HALT(n)`, *n* 1 to 255, with `%X10000000 + 8*n + 2`, so a trap with
    code *c* ends as `HALT(c)` does, with its message. That matches the
    LLVM targets, where a trap's exit status is its code. A procedure
    recovers *n* as `($STATUS .AND. %XFFF8) / 8`. This settles
    `000-todo.org`'s "what HALT(n)'s status means on VAX/VMS".
11. **Order of work**: open arrays (1); `Out` (2); pointers, `NEW` and
    descriptors without extension (3, 4); records holding pointers, and
    `VAR` record parameters (5); extension, `IS`, guards and `WITH` (4);
    type-bound procedures (6); procedure values (7); nested procedures
    (8); reals (9); the traps (10) as each construct brings one, and the
    real `POC_TRAP` and `POC_HALT` as soon as `Out` exists; then
    `ASSERT` and `SYSTEM.SET64`. Each sub-step gets fixtures shared with
    the LLVM suite once `Out` exists. The survey is re-run after each,
    and the step ends when poc's own source is written with no refusal.

**Done: open arrays (item 1), 2026-10-09.** `VaxCodeGenerator` lowers
open-array parameters of any number of open dimensions, by value or
`VAR`. The caller passes the address, then one longword per open
dimension's length: a literal's length counts its 0X, and an open array
passes on its own lengths. A value parameter is copied at entry. Its
size (the lengths times the element size, rounded up to a longword) is
subtracted from `SP`, the copy's address is kept in the frame, and
`MOVC3` moves the bytes in pieces of at most 65,535. Only the operations on
characters know about 0X: a literal's length counts it, `COPY` stops at
it, and `=` compares strings. Everything else works from the lengths
times the element size, whatever the element type. Elements are reached
through that address (`@off(FP)[Rx]`) or through the parameter's
(`@off(AP)[Rx]`). Each index is checked unsigned against its length
(trap 2). `LEN` reads the length longword, giving a `LONGINT` (a quadword
under `-OC`). `COPY` to or from an open array takes the smaller of
`LEN(dst) - 1` and the source's length, finds 0X with `LOCC`, moves that
many bytes and ends with 0X, as step 7 does for fixed arrays. `=` and
the other comparisons pass both lengths to `POC_STRCMP`. Assigning an
open array to a fixed one traps with code 9 when it is too long, before
anything moves. An external procedure's open-array parameter is still
refused, since Phase 17 chooses its mechanism (step 5 did: by reference,
an open `ARRAY OF CHAR` by descriptor; `vms-sdl-interfaces.md`, part 1). Fixture `vax-open-arrays`
tests all of this. Its debugger runs cover both traps, and the program is
built and run on the guest under `-O2` and `-OC`, with all 11 checks
holding. Two of the checks use `ARRAY OF INTEGER`, for the copy at entry
and for assignment.

Re-running the survey leaves 19,443 refusals in poc's own source and none
of them is an open array. The 182 that mention `ARRAY OF` are pointers
to arrays. The total fell by less than the 4,340 open-array refusals,
because procedures that used to be refused whole are now examined, which
shows more pointer refusals: 14,659 in all now. A few refusals follow on
from a pointer refused earlier in the same expression: 12 of `ORD` and
one register-pressure refusal in `VaxTypes.SameName`.

**Done: a minimal `Out` (item 2), 2026-10-09.** `rtl/vax/Out.Mod` has
`Open`, `Flush`, `Char`, `String`, `Ln`, `Int` and `Hex`, with the LLVM
`Out`'s interface and output (`FormattedText`'s `Int` and `Hex`). It
keeps a line of up to 1,024 characters until `Ln`. Then
`POC_PUT_LINE(text, length)` in `PocRtl.mar` writes the line as one record
with `LIB$PUT_OUTPUT`, through a string descriptor made on the stack. A
longer line is written in records of 1,024 characters. `Flush` does
nothing, as on LLVM, since writing part of a line would end the record
there. `Out`'s body passes the addresses of its line and length to
`POC_OUT_REGISTER`, which declares an exit handler (`$DCLEXH`). The
handler writes a line the program left without `Ln`, as a record of its
own. The length is a `LONGINT`, and the runtime reads its low longword,
so `Out` compiles under `-O2` and `-OC` alike. `Real`, `LongReal` and
`Ten` are still to come, now that reals are lowered (item 9), and
`IsConsole` for step 4. There are no VMS libraries yet (Phase 17), so a
program finds `Out` as source with `-import-path rtl/vax`, and `-build`
writes `Out.mar` with the program's modules.

Fixture `vax-out` builds one program with the LLVM backend and runs it
on the host, then builds it for the VAX and runs it on the guest, under
`-O2` and `-OC`. For each model, both runs must print the same expected
output. The fixture also has `Out.mar` reviewed (`expected-vax-Out.mar`),
and a program whose last line is written by the exit handler.

Comparing the two backends' output found a bug: the voc-built poc wrote
the high longword of `MIN(HUGEINT)` as `^X7FFFFFFF`, because voc's `DIV`
is wrong for a dividend near `MIN(LONGINT)` (vishap-bugs 07). `HalfText`
now uses `ASH`. The Stage 1 poc was always right. No earlier fixture used
the constant, so the two compilers' suites never disagreed. The survey is
unchanged at 19,443 refusals.

**Done: pointers, `NEW` and descriptors without extension (items 3 and 4),
2026-10-09.** A pointer is a longword, the address of the block's data,
and `NIL` is 0. A pointer to a record without a base type, or to any
array, is lowered. A pointer to an extension waits for extension (item
11's next steps). Each dereference, written or implied by a field or an
index, moves the pointer to a register, which sets the condition codes,
then `BNEQ` over a call of `POC_TRAP` with code 4 at the designator's line
and column. The LLVM backend reported `a[i]^`'s at the index expression
until 63f53c1; both now give the designator's. `NEW(p)` builds an argument
list in the frame and calls `POC_NEW(size, tag)` in `PocRtl.mar`, which
takes the size and a tag longword from `LIB$GET_VM`, stores the tag,
zeroes the data in pieces of 65,535 bytes and returns the data's address,
or 0 when `LIB$GET_VM` fails, which leaves `p` `NIL`, as on LLVM without
`-trap-heap-exhausted`. Nothing is freed until step 4 ports the collector.
`NEW(p, n0, ...)` of an open array checks each length to be positive and
the size (the lengths times the element's size, by `EMUL`, plus a longword
per dimension, rounded up as the element needs) to be below 2^31, else
trap 7, since P0 space is 1 GB. The LLVM targets of 32 bits trap only from
4 GB. When `POC_NEW` returns a block, the lengths are stored in its
header, and `LEN(p^)` and the index checks read them there. The driver no
longer adds LLVM's `GarbageCollectedHeap` and `ModuleTable` to a program
for the VAX that calls `NEW`. (Since step 4, `NEW` calls the collector's
`Allocate` instead, and the driver adds `rtl/vax`'s `GarbageCollectedHeap`:
section 15, "Done: the collector".)

A type descriptor is written in `POC_CONST` as LLVM lays it out, every
field a longword: the size, the extension level (0 so far), the pointer
count, the base types (only the descriptor's own address, at level 0) and
the pointers' offsets. There is no `ProcTab` until type-bound procedures
(item 6). Every record type declared at a module's level has one, and so
does a pointer's record base declared in the pointer type, named
`<Module>.<Type>.base` (§5's scheme). They are all global, not only the
exported ones as item 4 said: an exported pointer type may be bound to a
record type that is not exported, and its importers' `NEW` names the
record's descriptor, `G^` and `.EXTERNAL`. A record type declared in a
procedure gets a local `L_TD_n` when `NEW` needs one, and an array, fixed
or open, whose elements hold pointers an `L_AD_n`, whose size is one
element's. `NEW`
of anything else passes the tag 0, as the collector will have nothing to
trace in it. MACRO and LINK take `.ADDRESS` in `POC_CONST`, though it is
`PIC`, without a message.

Fixture `vax-pointers` has two modules reviewed: `VaxPointers` and
`VaxPtrLib`, which exports a pointer bound to a record it does not
export. Its debugger runs examine what the program computes through
pointers, read three tags, which the debugger names by their descriptors,
and take both traps, 4 and 7. A second program, `PointersOut`, prints
with `Out` and is built by both backends under `-O2` and `-OC`, run on
the host and on the guest, and must print the same output.
`vax-declarations-only`, `vax-records` and `vax-modules`' `VaxModLib` now
have descriptors, so their `expected-vax.mar` were reviewed again.
`vax-emit-errors`' `VaxReportedOnce` takes a procedure variable for its
unlowerable operand where it had a pointer.

Re-running the survey leaves 10,859 refusals in poc's own source, down
from 19,443. Most are pointers to extensions (7,630 refusals of a value,
variable, parameter or assignment of such a type), `IS` (309), `WITH`
(25) and type guards (7), and the records holding such pointers,
`LLVMCodeGenerator.Codegen` (1,738) and `Parser.Parser` (495), which are
items 5 and 11's next steps. Reals account for 156, procedure variables
for 55, nested procedures for 7. Code that was refused whole is now
examined, so 51 refusals for lack of registers show up (the largest
expressions and calls), and 20 `SYSTEM.BYTE` parameters.

**Done: records holding pointers and `VAR` record parameters (item 5),
2026-10-09.** A record holding pointers to records without a base type,
or to arrays, was already lowered with the pointers: its descriptor
lists the pointers' offsets, those of nested records and fixed arrays
included, and a local one starts NIL, the frame being cleared on entry.
A `VAR` record parameter of an Oberon procedure now takes its actual's
type tag as a hidden longword right after the address, as on LLVM
(`NeedsHiddenTag`), and the parameters after it move up a longword. An
external `"VMS"` procedure's takes the address alone. The tag is the
parameter's own when a `VAR` record parameter is passed on as it is; the
block's, the longword before the record, when the actual ends in `^`;
otherwise the descriptor of the actual's static type, `G^` and
`.EXTERNAL` for an imported one, and 0 for an unnamed record type of
another module, which this module cannot name (LLVM passes `null`).
Nothing reads a tag yet. Assigning a record to a `VAR` parameter or to
`p^` will compare the tag with the static type's descriptor (trap 13)
when extension makes them differ, as on LLVM, and `IS`, guards, `WITH`
and type-bound procedures will read it.

Fixture `vax-var-records` has `VaxVarRecords` and `VaxRecLib` reviewed.
Its debugger runs examine what the program computes and, breaking in
`Twice`, `Grow` and `VaxRecLib.Count`, the tags each one receives, which
the debugger names by their descriptors. A second program, `VarRecOut`,
prints with `Out`, and is built by both backends under `-O2` and `-OC`
and must print the same. `vax-records` and `vax-modules` pass the tag
now, so their `expected-vax.mar` and `VaxModLib`'s were reviewed again,
and the runs' listing line numbers moved.

The survey counts 10,889 refusals. Outside `VaxCodeGenerator.Mod` it is
unchanged at 9,703: no `VAR` record parameter was refused before, as it
passed its address, and the 30 more are in the code added for the tags,
which uses pointers to extensions.

**Done: extension, `IS`, type guards and `WITH` (item 11's next step),
2026-10-09.** A record with a base type is lowered, with pointers to it.
Its fields follow its base type's, and an inherited field is at its
offset in the record that declares it: `VaxTypes.FieldOffset` finds that
record first, since `MemoryLayout.FieldOffset` counts only the fields of
the record it is given. A descriptor now has its extension level, how
many base types the record has, and after the pointer count its base
types' descriptors, the root first and its own last, `BaseTypes[L]` at
`12 + 4L` (item 4). Another module's is its symbol, `.EXTERNAL`, and a
record declared in a procedure gets an `L_TD_n` whenever a descriptor
lists it.

`IS` and a guard on a pointer check it for `NIL` (trap 4 at the
designator), load the block's tag, the longword before its data, and
test it as on LLVM: the descriptor's level at least the type's, `L`, and
its `BaseTypes[L]` the type's descriptor. The level test is left out
when `L` is 0. The result is a byte register, 1 when both hold. On a
`VAR` record parameter the tag is its hidden one (item 5), and a guard
of a record is allowed nowhere else, as in the front end. A guard that
fails traps with code 5 at the guarded designator. The variable is then
used with the guard's type, dereferenced again for a field, so its `NIL`
check is repeated. The call form, `v(T)` as a value or as a `VAR`
argument, is a guard too, as on LLVM (`IsGuardExpr`), and a guarded
`VAR` record parameter passed on keeps its own tag.

`WITH` tests its guards in turn. The first that holds runs its
statements with the variable of the guard's type, the record type for a
`VAR` record parameter, the pointer type for a pointer, then jumps to the
end. With none, the `ELSE` part runs, or without one trap 6 is raised.
Its `NIL` checks and trap 6 are at the `WITH`. The parser gave the
`WITH` the position of its last `|`, so the LLVM backend's
`-trap-location` reported trap 6 there after a `WITH` of more than one
guard (`llvm-trap-location`'s `WITH` has one); it now keeps the
`WITH`'s, and each guard its own, as `IF` does.

An assignment to a record whose dynamic type may differ from its static
type, a `VAR` record parameter, guarded or not, or `p^`, first compares
the tag with the static type's descriptor, and traps with code 13 at the
statement when they differ (Oberon2.pdf 9.1), as on LLVM. A record with
no name of its own cannot be extended, so it is not checked. A record
assignment copies the target's size, so assigning an extension to its
base type copies only the base's fields. An array still copies the
source's, which may be shorter.

Fixture `vax-extension` has `VaxExtension` and `VaxExtLib` reviewed.
Its debugger runs examine what the program computes, the tags of two
blocks and one descriptor's level and base types, and take each trap:
5, 6, 13 three ways, and 4 from `IS`. A second program, `ExtensionOut`,
prints with `Out`, and is built by both backends under `-O2` and `-OC`
and must print the same. No earlier fixture changes.

The survey counts 388 refusals, down from 10,889, none of them about
extension: procedure values and calls of procedure variables (118),
reals (165), `SYSTEM.BYTE` parameters (78), calls and expressions that
need more registers than are left (19), nested procedures (7) and a
structured constant (1). poc's source has no type-bound procedures.
Writing it showed that voc takes an `ARRAY OF CHAR` for a value
parameter of type `ARRAY 256 OF CHAR`, which Oberon-2 and poc reject,
and copies the formal's 256 bytes from it (vishap-bugs 68), so the
survey is also a check that the backend's own source is poc's
Oberon-2.

**Done: type-bound procedures (item 6), 2026-10-09.** A type-bound
procedure is an ordinary procedure named by the symbol of
`<Module>.<Type>.<P>`, `<Type>` being the record it is bound to, a
pointer receiver's too, as on LLVM (§5). It is always `.ENTRY`, global,
since an importer's descriptor may name it even when it is not exported.
Its receiver is its first argument: a pointer, or for a `VAR` receiver
the record's address and then its tag, as for any `VAR` record parameter
(item 5). A receiver the procedure changes is copied to the frame, as a
value parameter is. `-dump-vax-names` named a pointer receiver's
procedure after the pointer type; it now names it after the record, as
the code does (`vax-names`).

A record's descriptor now has its `ProcTab` below the tag, slot *i* at
`-4(i+1)`, so the last slot is written first, each slot the symbol of
the procedure the record has there, its own or inherited
(`LLVMTypes.MethodSlotCount` and `SlotMethod`, which the VAX backend
imports). A procedure of another module is its symbol, `.EXTERNAL`. A
record with no type-bound procedures has no `ProcTab`, so no reviewed
`.mar` file changes.

A call `v.P(...)` follows LLVM's choice (`FindMethodTarget`). A record
variable, field or element has its static type, so its procedure is
called directly, with that type's descriptor as the tag. So is `v.P^`,
the base type's procedure. Any other receiver, a pointer, `p^`, or a
`VAR` record parameter, guarded or not, may have another dynamic type,
so the call goes through the `ProcTab` of its tag: the tag into `R1`, the
block's `-4(Rn)` or the parameter's own, then `CALLG list,
@-4(i+1)(R1)`. A pointer receiver is checked for `NIL` first (trap 4 at
the receiver). A procedure with a pointer receiver called on a record
that is not a heap block is refused, as on LLVM.

Fixture `vax-type-bound` has `VaxMethods` and `VaxMethLib` reviewed.
Its debugger runs examine what the program computes and `SquareDesc`'s
`ProcTab`, and take trap 4 from a pointer and from a `VAR` receiver's
block and trap 5 from a guarded receiver, at the positions the LLVM backend's `-trap-location` gives. A second program,
`MethodsOut`, prints with `Out`, and is built by both backends under
`-O2` and `-OC` and must print the same. `vax-emit-errors` no longer
expects a type-bound procedure to be refused. The survey still counts
388 refusals, since poc's source has no type-bound procedures.

**Done: procedure values (item 7), 2026-10-09.** A procedure type is a
longword, the address of a procedure's entry mask, and `NIL` is 0. A
procedure taken as a value is `MOVAB` of its symbol: a private one's
local label, at its `.WORD` mask, an exported one's `.ENTRY`, and
another module's in general mode, `G^`. `MOVAB` writes straight into the
variable assigned, or into the argument list's entry for a procedure
passed as an argument. `=` and `#` compare two procedure values, or one
and `NIL`, as longwords. The front end allows only global Oberon
procedures as values, so no external procedure, and no environment, is
ever one (item 7).

A call through a value, a variable, parameter, field or element of
procedure type, evaluates the value first, as LLVM does, into a register
from `R2` up, which the call does not have to move, and checks it for
`NIL`: trap 4 at the designator's line and column, an element's too, as on
LLVM since 63f53c1 (item 3). Then the argument list is built from the
procedure type's parameters, as for a direct call, so a `VAR` record
parameter's tag, an open array's lengths and a quadword's copy are passed
as the procedure expects, and the call is `CALLG list, (Rn)`, or `CALLS
#0, (Rn)` with no arguments. A value spilled to the frame while the
arguments are evaluated would be called as `@n(FP)`. The analysis of which
value parameters a procedure changes now reads a call through a value's
parameter list from its type, so passing a parameter by value through one
does not copy it to the frame.

Fixture `vax-procedure-values` has `VaxProcVals` and `VaxProcLib`
reviewed. Its debugger runs examine what the program computes and what
four variables hold, which the debugger names by their procedures, one of
them a procedure `VaxProcLib` does not export, and take trap 4 from a
`NIL` variable and a `NIL` element of a pointer's array. A second program,
`ProcValsOut`, prints with `Out`, calling `Out.String` and `Out.Ln`
through values too, and is built by both backends under `-O2` and `-OC`
and must print the same. `vax-emit-errors`' `VaxTooMuch` no longer passes
a procedure as a value, and `VaxReportedOnce` takes a pointer to a record
with a field initializer for its unlowerable operand.

The survey counts 270 refusals, down from 388, none of them procedure
values: reals (165), `SYSTEM.BYTE` parameters (78), calls and
expressions that need more registers than are left (19), nested
procedures (7) and a structured constant (1).

**Done: nested procedures (item 8), 2026-10-09.** A procedure with
procedures nested in it is the root of `NestedProcedures.Analyze`'s tree,
as on LLVM, which gives each nested procedure, in source order, the
variables of the enclosing procedures it needs: those it names, those a
procedure nested in it needs, and those a nested procedure it calls needs,
less what it declares itself. Each nested procedure is lifted to a
procedure of its own, written after its root, parents first (before its
root until Phase 18 step 5a, which needs each routine after the one it is
nested in: `vax-object-language.md`, section 16.5), as a local
label and `.WORD` of its mask, since only its enclosing procedures can
call it and it is never a procedure value. Its symbol is made from its
root's full name and its path below it, `VaxNested.Deep.Middle.Inner`, or
`VaxNested.CounterDesc.Bump.Once` in a type-bound procedure, so two
procedures may each have a nested one of the same name.
`-dump-vax-names` now lists them (`vax-names`).

After its own parameters, a nested procedure takes one group of hidden
longwords per variable it needs, in its needs order: the variable's
address, then, as a parameter of its kind has them, a `VAR` record
parameter's tag (a `VAR` receiver's too) or an open array's lengths. It
binds each as a `VAR` parameter, so every access, `IS`, guard, `LEN` and
index check works through `@n(AP)` as it does for one. A call passes, for
each variable the callee needs, what the caller has for it: the address
of its own local, the address it was itself given, or an open-array
value parameter's copy, with the tag or lengths beside it. The caller
always has one, since what a procedure needs includes what the nested
procedures it calls need. A value parameter or receiver that a nested
procedure needs is copied to the frame on entry, since the nested one may
assign it and the argument list is the caller's. A variable of a
procedure that the one being generated has no binding for is reported
rather than taken for a module variable.

Fixture `vax-nested` has `VaxNested`, reviewed: a local read and
written, three levels where the middle one never names what the inner
one reads, siblings in mutual recursion through a forward declaration,
a cousin called, value and `VAR` parameters, a `VAR` record parameter
with `IS` and a guard, value and `VAR` open arrays, `HUGEINT`s,
a type-bound procedure's receiver, the enclosing procedure's own
recursion, a list built by a nested procedure, and two nested procedures
of one name. Its debugger runs examine what it computes and take trap
4 from a receiver a nested procedure set to `NIL`, and trap 2 from
an enclosing procedure's open array. A second program, `NestedOut`,
prints with `Out`, and is built by both backends under `-O2` and `-OC`
and must print the same. The trap 4 is reported at `c` in `INC(c.n, k)`,
and trap 2 at the index, both where LLVM's `-trap-location` gives them.
`vax-emit-errors`' `VaxTooMuch` no longer has a nested procedure.

The survey counts 263 refusals, down from 270, none of them nested
procedures: reals (165), `SYSTEM.BYTE` parameters (78), calls and
expressions that need more registers than are left (19) and a structured
constant (1). The nested procedures' bodies, examined for the first time,
add none.

**Done: reals (item 9), 2026-10-09.** A `REAL` is an F_floating
longword (`.BLKF`) and a `LONGREAL` a G_floating quadword (`.BLKG`), held
in a register pair as a quadword is, passed by the address of a copy as a
`HUGEINT` is, and returned in R0 and R1; a `REAL` is passed and returned
as a longword. Arithmetic is `ADDx`, `SUBx`, `MULx` and `DIVx` at the
wider of the two types, an integer converted by `CVT`, a quadword by the
runtime's `POC_QTOG`; `/` of two integers is a `REAL`. A relation is
`CMPF` or `CMPG` with the signed branches, which are right since `CMP`
sets N and Z as for signed integers and clears V and C (MACRO 9.2.8.4).
`ABS` is `MNEGx` after a test, `LONG` is `CVTFG` and `SHORT` `CVTGF`,
neither checked. `ENTIER` checks its argument against -2^31 and 2^31
under `-O2`, or -2^63 and 2^63 under `-OC`, with trap 8 as on LLVM, then
floors: `CVTxL`, converted back, and `DECL` when that is more than the
argument; under `-OC` the runtime's `POC_ENTIERQ` gives the quadword.

A constant is an immediate whose decimal text MACRO converts, so it is
rounded once, as the VAX rounds: the numeral as written, its `D` made
`E`, when it is shorter than 32 characters, otherwise `FormatReal`'s
shortest text of its value (now exported by `ModuleInterface`), and zero
as `0.0`, since MACRO assembles `#-0.0` with the sign bit set, a reserved
operand. MACRO V5.4-3 on the guest rounds a halfway literal away from
zero, makes an underflowing one 0 without a message, and rejects one
past the format's range with `%MACRO-E-FLTPNTSYNX`. So `MAX` and `MIN`
of a type, IEEE 754's bound, are written as the VAX format's largest
value, half of it, and any other constant past that is an error, "a
LONGREAL constant too large for the VAX, whose largest LONGREAL is
8.988465674311579E307" (`vax-emit-errors`' `VaxRealRange`). A `REAL`
constant in a `LONGREAL` operation is widened by `CVTFG` at run time,
as LLVM's `fpext` widens it, so it keeps a `REAL`'s precision. A real
overflow or division by zero is the hardware's fault (`SS$_FLTDIV_F`),
not a trap of poc's.

For step 6: `ConstantEvaluator.MaxLongReal` computes (2^1023 - 2^970) *
2, IEEE 754's largest double, which is about twice G_floating's largest
value, so poc running on the VAX will overflow there and must compute
the VAX bound instead. `Out`'s `Real`, `LongReal` and `Ten` are still to
come.

Fixture `vax-reals` has `VaxReals`, reviewed: constants as written and
as computed, arithmetic with integers and a `HUGEINT` converted, every
relation, `ABS`, `LONG`, `SHORT` and `ENTIER` of positive and negative
values, value and `VAR` parameters, results, a call while a `LONGREAL`
waits in a register pair, a procedure variable, record fields, an open
array, and an expression that spills a pair. Its debugger runs examine
what it computes, and that 2^53 + 1, a `HUGEINT` converted and a sum, is
2^53 + 2, a halfway case rounded away from zero (MACRO 9.2.8.3), where
IEEE 754 rounds to even, 2^53. Then they take trap 8 from `ENTIER` of
3.0D9, at the column LLVM's `-trap-location` gives, and the floating
divide-by-zero fault. A second program, `RealsOut`, prints the same
checks but the rounding one with `Out`, and adds `ENTIER` of values past
2^31; it is built by both backends under `-O2` and `-OC`, and must print
the same.

The survey counts 78 refusals, down from 263, all of them `SYSTEM.BYTE`
parameters. The 19 calls and expressions that needed more registers than
were left went with the reals: they followed refused `LONGREAL` calls in
one procedure of `ConstantEvaluator`, whose registers stayed held. The
structured constant went too: it was `ZeroValue`'s `0.0`.

**Done: the real `POC_TRAP` and `POC_HALT` (item 10), 2026-10-09.**
`rtl/vax/PocRtl.mar`'s `POC_TRAP` writes the LLVM backend's message for
the trap's code, one record, to `SYS$ERROR`: RMS `$CREATE` and
`$CONNECT` of a FAB naming `SYS$ERROR`, which gives indirect access to
the process-permanent file, or makes the file it is defined as, and
`$PUT` of a variable-length record with carriage-return carriage control
(RMS 4.1 and 5.23). Then it exits with `%X10000000 + 8*c + 2`.
`POC_HALT` exits with `SS$_NORMAL` for `HALT(0)`, else with the same
status for *n*. `$EXIT` runs the exit handlers (System Services,
`$DCLEXH`), so `Out`'s unfinished line is still written. Two codes have more than one message: 14 is
`SHORT`'s and `CHR`'s. So the call passes the code in the low word of its
longword, and in the high word which message: `CHR`'s code is pushed as
`#^X0001000E`. `ASSERT`'s *n* can go there too. The debugger stub keeps
only the low word, so the runs' logs are unchanged.

Under `-trap-location` the call has two more arguments, so that the
message is LLVM's, `file:line:column: message (in procedure)`:
`L_FILE_NAME`, a counted string of the file as the driver opened it, and
`L_WHERE_<n>`, one for each procedure with a trap, named as LLVM names
it (`Module.P`, `Module.Record.Method`, `Module.P.Inner`, or `Module,
module body`). `POC_TRAP` tells the forms apart by its argument count
and formats the longer one with `$FAO`'s `!AC` and `!UL` (System
Services, `$FAO`). Without the switch the call is as before, so no
earlier fixture's `.mar` changed, except `vax-range-checks`', for
`CHR`'s code.

Fixture `vax-traps` has `VaxTraps`, reviewed, under `-trap-location` and
`-range-checks`: the strings and the six arguments for a type-bound
procedure, a nested one, its parent and the module body, and `CHR`'s
code beside `SHORT`'s. A second program, `Traps`, is built by both
backends and run once for each case, chosen by a module `TrapMode` that
`test.sh` writes: `CASE`, NIL, a guard in a nested procedure, an index
in an imported module, `ENTIER`, `CHR`, `SHORT`, `HALT(0)` and
`HALT(7)`. Each case's output, status and message must be the same, the
VAX's status converted from LLVM's exit status by item 10's rule. The
cases run with and without `-trap-location`, the VAX ones with
`SYS$ERROR` defined as a file so that the message is printed after the
output. `vax-range-checks`' `.mar` was reviewed again for `CHR`'s code.

**Done: `ASSERT` (item 11), 2026-10-09.** `ASSERT(x)` branches on `x`
as `IF` does (`JumpOn`), to a call of `POC_TRAP` with code 10 at the
statement's line and column, as LLVM's statement trap is. `ASSERT(x, n)`
puts *n* + 1 in the code's high word, as `CHR`'s code chooses its message
(item 10): `#^X0001000A` for 0, `#^X0100000A` for 255. `POC_TRAP` then
writes `assertion failed (n)` with `$FAO` into a counted string of its
own, and `assertion failed` for 10 alone. The status is the trap's,
`%X10000052`, as LLVM's is 10 whatever *n* is.

Fixture `vax-assert` has `VaxAssert`, reviewed: `ASSERT` of a relation,
of `&` and of `OR`, with and without *n*, `ASSERT(TRUE)`, and one in a
procedure. A second program, `Asserts`, is built by both backends and
run once for each case, with and without `-trap-location`: `ASSERT(x)`,
`ASSERT(x, 0)`, `ASSERT(x, 255)` in a procedure, and one where every
assertion holds. Each case's output, status and message must be the
same. `vax-emit-errors`' `VaxTooMuch` now has `SYSTEM.GET` where it had
`ASSERT`, as a predeclared procedure still refused. poc's own source has
no `ASSERT`, so the survey is unchanged: 78, all `SYSTEM.BYTE`
parameters.

**Done: `SYSTEM.SET64` (item 11), 2026-10-09.** A `SET64` is a quadword,
element *n* bit *n* `MOD` 32 of longword *n* `DIV` 32, lowered as a
`HUGEINT` is: in a register pair or two longwords of memory, a constant
two `MOVL`s. `+`, `-`, `*` and `/` are `BISL2`, `BICL2`, `BICL2` of
`MCOML` and `XORL2` on each longword, unary `-` `MCOML` of each; `=` and
`#` compare the two longwords. A `SET` with a `SET64` is zero-extended
(`MOVL`, `CLRL`), as a `SET` is included in a `SET64`. A constructor is a
`SET64` only when a constant element is above 31, as
`SemanticActions.CheckConstantSetElement` types it and LLVM generates
it: a variable element `e` is `ASHQ e, #1`, a range `lo..hi` -1 shifted
`lo` places less -2 shifted `hi` places, both built by `MNEGL` on each
longword so that no quadword immediate but a short literal is needed;
the constant elements are `BISL2` of the longword holding them. `IN` is
`FALSE` outside 0..63 (`CMPL #63`, `BGTRU`). `BBC` takes any bit of
memory but only bits 0..31 of a register, a larger position being a
reserved operand (MACRO 9.2.3), so for a set in a register pair a
constant element tests its bit in the register holding it, and a
variable one shifts the pair right (`ASHQ` of the negated element) and
tests the low bit (`BLBC`). `INCL` and `EXCL` are `BISL2` or `BICL2` of
a constant's bit in its longword, or of `ASHQ x, #1` on both. `ORD` of a
`SET64` is its `HUGEINT`, a `MOVQ` (`PredeclaredProcedures.CheckOrd`).

Fixture `vax-set64` has `VaxSet64`, reviewed, with each lowering once,
and `Set64Out`, built by both backends under `-O2` and `-OC` and run,
whose output must be the same: constructors, the operators, `IN` with
elements in and out of 0..63, `INCL` and `EXCL`, comparisons, and
`SET64` parameters, results, record fields and array elements. `vax-emit-errors`' `VaxTooMuch` and `VaxReportedOnce` now use a
record with a field initializer where they had a `SET64`. poc's own
source has no `SET64`, so the survey is unchanged: 78, all `SYSTEM.BYTE`
parameters.

**Done: `SYSTEM.BYTE` parameters, 2026-10-10.** `SYSTEM.BYTE` is a byte,
`B`, in the slice as `CHAR` is. A value `BYTE` parameter is passed as a
longword, as any byte is (section 7): a `CHAR` zero-extended, a
`SHORTINT` sign-extended, and the callee reads its low byte. A `VAR` one
takes the variable's address. A `VAR ARRAY OF SYSTEM.BYTE` takes any
variable (Oberon2.pdf, Appendix C), passed as an open array is, with one
length: the variable's size in bytes, as LLVM's
(`GenerateOpenArrayArg`). For a variable of fixed size it is a
constant. For an open array it is the lengths multiplied by `MULL2`, and
then by the element's size.

Fixture `vax-byte-params` has `VaxBytes`, reviewed, with each lowering
once. A second program, `BytesOut`, is built by both
backends under `-O2` and `-OC` and run, and the two outputs must be the
same. It copies through `BYTE` parameters, prints each byte of an integer,
a `HUGEINT`, a record, a fixed array, an open one and a two-dimensional
one, and fills arrays. It uses only types of one size under both models;
both targets are little-endian. No earlier fixture changes.

The survey of poc's own source (`src/`) counts no refusals. The 179 left
are all in `rtl/llvm`, which step 4 replaces: `SYSTEM.VAL` and
`SYSTEM.ADR` (48 each), `["C"]` externals (47), `SYSTEM.GET` (20) and
`PUT` (9), and quadword value parameters of externals (7).

**Step 3 closed, 2026-10-10** (the user). poc's own source is written
for the VAX with no refusal, as item 11 said the step would end. What is
left of the survey is `rtl/llvm`'s, which step 4 replaces (section 15).

## 15. The VAX runtime (Phase 16 step 4)

Step 4 writes `rtl/vax`: what poc's own source needs from its runtime,
for VAX/VMS, so that step 6 can build poc there. This section is the
survey and the proposals, written for the user's approval before any of
it is done, as section 14 was. **Approved by the user, 2026-10-10.**

**The survey.** poc's own source imports five runtime modules directly,
and through them six more (`ModuleTable`, `FileDescriptorOutput`,
`GarbageCollectedHeap`, `RealDigits`, `FormattedText`,
`FormattedOutput`), which are `rtl/llvm`'s own structure, not poc's
needs. What `src/` calls, with the number of uses:

| Module | Used by poc's source |
|---|---|
| `Files` | `File`, `Rider`; `Old` (26), `New` (11), `Register` (7), `Close` (27), `Set` (23), `Read` (8), `ReadLine` (11), `ReadString` (1), `Write` (72), `WriteString` (2), `Length` (4), `Delete` (2), `Base` (1) |
| `Platform` | `System` (13), `Unlink` (12), `Chdir` (7), `CWD` (5), `PID` (4), `GetEnv` (3), `Exit` (1) |
| `Out` | `String`, `Ln`, `Int`, `Char` |
| `Err` | `String`, `Ln`, `Int`, `Char` |
| `Modules` | `ArgCount`, `GetArg` (argument 0 is the program's own path, from which the library path's default is found), `Init` |

`Platform.System` runs clang, `ar`, `cp` and `mkdir`: the LLVM
toolchain, libraries and `-output-dir`'s directory. The 58 places where
`src/` joins a directory and a file name put `/` between them.

**Checked on the guest (2026-10-10)**, with `tools/vax-do`:
- A foreign command (`FOREIGN := $dir:FOREIGN.EXE`) gets its line from
  `LIB$GET_FOREIGN` with the unquoted text uppercased and each run of
  spaces made one: `FOREIGN -build -o Hello Mixed.Mod` gives `-BUILD -O
  HELLO MIXED.MOD`. Quoted text keeps its case, and the quotes are kept:
  `"-o" "Hello"` gives `"-o" "Hello"`, `a"b"c` gives `A"b"C`, and `"x""y"`
  stays as it was.
- `MACRO` assembles a Stream_LF `.MAR` file (record format `STMLF`,
  attributes `CR`, made by `CONVERT/FDL`), and `LINK` reads a Stream_LF
  options file. The image runs. A file FTP sends in ASCII mode is
  variable-length (`VAR`, `CR`).

Proposals:

1. **Shape.** `rtl/vax` gets the five modules poc imports, each with the
   exported names and signatures poc uses, so that poc's source compiles
   unchanged against either runtime. Each is Oberon-2, calling `LIB$`
   and `SYS$` routines as `["VMS"]` externals where a string descriptor
   or a longword is all they take. The rest goes in `PocRtl.mar`, where
   the STARLET macros (`$FAB`, `$RAB`, `$NAM`) lay out the control blocks:
   RMS file access, the stack base, and saving registers for the
   collector. The six internal modules are not ported as they are; what
   `Out` and `Err` share is one module of its own (as `Out` is now, over
   `POC_PUT_LINE`).

2. **Files over RMS.** A file poc creates is Stream_LF (`RFM=STMLF`,
   `RAT=CR`). It is written and read with block I/O (`$WRITE`, `$READ`),
   so every byte round-trips exactly, a `.sym` file's included. MACRO,
   LINK and `TYPE` read it as text (checked above). A file of another
   record format is read a record at a time (`$GET`), with an LF (`0AX`)
   after each record. Such files are variable-length or VFC (from FTP in
   ASCII mode, or written by an editor), so a source written on VMS reads
   as it does on Unix. A fixed-length file is read as raw bytes. A
   `Rider` keeps a buffer of one block (512 bytes); `Set` positions it,
   and `Length` is the byte count from the file's end-of-file block and
   first free byte. `Register` gives the new file its name, as a new
   version. A file is never written in place.

3. **File names.** A name is given to RMS as it is: case does not
   matter, and a missing version means the highest. A module's `.Mod`,
   `.sym` and `.mar` names fit ODS-2 (39 characters for the name, 39 for
   the type; letters, digits, `$`, `_`, `-`) unless the module's name is
   longer than 39 characters, which the VAX target makes an error. Two
   modules whose names differ only in case are already one
   (section 5.1). `Platform.Unlink` and `Files.Delete` delete the
   highest version only, as `$ERASE` does when no version is given
   (confirmed on the guest, below), so an older build is left in place,
   as VMS leaves it. Old versions pile up until the user purges them.

4. **Directories.** A new module, `Directories`, holds what follows
   (amended 2026-10-10, decided with the user: these were to be added
   to `Platform`, but the Stage 0 poc is built by voc against voc's own
   `Platform`, which has none of them; `rtl/voc/Directories.Mod` gives
   that poc the same interface over voc's `Platform`, and `Platform`
   keeps voc's). `Directories.MakePath(dir, name, VAR path)`
   replaces the 58 joins with `/`. On Unix it puts `/` between them,
   unless `dir` already ends in one. On VMS it puts nothing between them
   when `dir` ends in `:`, `]` or `>` (a device, a directory, or a logical
   name with its colon), and `:` when it does not (a logical name without
   one). The two `Chdir`-and-back tests of whether a directory exists
   become `Directories.IsDirectory(dir)`. On VMS that is a `$PARSE`
   of `dir`, because `SYS$SETDDIR` would change the process's default
   directory, which DCL keeps after poc exits. `-output-dir`'s `mkdir -p`
   becomes `Directories.MakeDirectory(dir)`: `LIB$CREATE_DIR` on VMS,
   the same `mkdir -p` on Unix. `CWD` is `SYS$DISK` and
   `SYS$SETDDIR`'s directory joined. Its two uses are the LLVM backend's
   (the debug directory) and a library's, neither of them on VMS.

5. **The import path and the environment.** `Platform.GetEnv(name)`
   reads a logical name (`$TRNLNM`, in the process, job, group and system
   tables), not a DCL symbol. When the name is a search list, its
   equivalence strings are joined with `,`. `,` is VMS's separator in
   `POC_IMPORT_PATH`, since a directory contains `:`. A new constant,
   `Directories.pathSeparator`, is `:` on Unix and `,` on VMS. So
   `$ DEFINE POC_IMPORT_PATH DUA1:[POC.SRC.FRONT],DUA1:[POC.RTL.VAX]` gives
   two directories, and so does a search list. (On VMS the logical name
   is `POC$IMPORT` since 2026-10-12, named as `POC$LIBRARY` is; section
   18.5.)

6. **The command line.** poc is a foreign command
   (`$ POC :== $DUA1:[POC]POC.EXE`); `Modules` takes `LIB$GET_FOREIGN`'s
   line and splits it at spaces outside quotes. A quoted argument loses
   its quotes, and `""` inside it is one `"`, as DCL's own rule has it
   (DCL Dictionary, DCL1-5). It keeps its case; unquoted text arrives
   in uppercase.
   Options are matched without regard to case (decided 2026-10-05,
   section 10); no two of poc's 31 options differ only in case. File
   names do not care. Argument 0 is the image's file specification
   (`$GETJPI`, `JPI$_IMAGNAME`). A DCL verb defined by a `.CLD` file is
   rejected: it needs `SET COMMAND` in every process, and its qualifier
   syntax (`/OUTPUT=`) is not poc's (`-o`).

7. **Running nothing.** On VMS poc runs no other program (step 2's
   decision): `-build` writes the `.COM` procedure. So `Platform.System`
   returns a failure there, without spawning. poc's default target on VMS
   is `vax-dec-vms` (`tools/build-info`), and an LLVM target is refused
   ("not available on VAX/VMS"), as `-library` already is.

8. **Exit, `Out` and `Err`.** `Platform.Exit(n)` exits as `HALT(n)`
   does: `SS$_NORMAL` for 0, `%X10000000 + 8*n + 2` otherwise, so poc's
   exit 1 after an error is an error status to DCL (`%X1000000A`).
   `Err` writes `SYS$ERROR` through RMS, as `POC_TRAP` does, one record
   for each `Ln`. Like `Out`, it writes a line left without `Ln` at
   exit. `Platform.PID` is `$GETJPI`'s `JPI$_PID`.

9. **The collector.** `GarbageCollectedHeap` is ported with its design
   (chunks, the start map, size-class free lists, conservative stack
   scanning, root tables, finalization). Chunks come from `LIB$GET_VM`.
   The stack grows down from the base the program's start saves.
   Registers R2-R11 are pushed by a `PocRtl.mar` routine (`PUSHR`)
   before the stack is scanned. Finalization at exit is an exit
   handler (`$DCLEXH`), not `atexit`. The VAX backend gains each
   module's root table of its pointer variables, registered when the
   module is initialised (as LLVM's are), and the main entry's call
   saving the stack base. `POC_NEW` then allocates from the collector.
   The heap's ceiling comes from the process's page-file quota
   (`$GETJPI`, `JPI$_PGFLQUOTA`, 5 MB for `POC`), so that the collector
   runs before VMS refuses memory. Whether poc fits in it is step 6's
   question (step 1's memory decision).

10. **Order of work and testing.** `Modules`, `Platform` and `Err` first,
    each with a fixture run on both backends where the output can be
    the same, and on the guest only where it cannot (argument splitting,
    logical names). Then `Files`, its fixture writing and reading back
    text and binary files, with variable-length sources made on the
    guest. Then the collector, its fixture allocating far beyond the
    quota. Changes in `src/` (`MakePath`, `IsDirectory`,
    `MakeDirectory`, `pathSeparator`, the 39-character check, the
    default target) are made on `vax`, with `rtl/llvm`'s new procedures
    beside them, checked on the four hosts. The step ends when poc's
    own source, with `rtl/vax`, builds into `POC.EXE` with `-build`, and
    that image starts and prints `-help` on the guest.

**Done: `Modules`, `Platform` and `Err` (proposal 10's first part),
2026-10-10.** Each is in `rtl/vax`, with a fixture: `vax-command-line`,
`vax-platform` and `vax-err`.

- *`Err` and `Out`* share `LineOutput`, which keeps a line for each
  stream until `Ln`. One exit handler writes a line left without `Ln`:
  `Out`'s first, then `Err`'s. `POC_PUT_ERROR_LINE` writes `Err`'s
  records to `SYS$ERROR` through RMS. `POC_TRAP` uses the same stream,
  so a trap's message follows `Err`'s lines. RMS's image rundown closes
  it (`$RMSRUNDWN`, System Services SYS-639).
- *`Err` is buffered here.* On LLVM it is not, so a line a program
  leaves unended comes after a trap's message on VMS.
- *`vax-out` changes.* Its `expected-vax-Out.mar` is now `Out`'s
  wrappers, and `expected-vax-LineOutput.mar` has the code that was
  `Out`'s. Every fixture that ships `Out.mar` to the guest now ships
  `LineOutput.mar` too.
- *`Modules`* splits `LIB$GET_FOREIGN`'s line as proposal 6 says. On
  the guest, `"two  spaces"` keeps both spaces, a tab separates
  arguments as a space does, and `""` is an empty argument. It has no
  `Init`, since the line comes from VMS, not from `main`.
- *`Platform`'s `ErrorCode`* is a VMS status: the whole longword under
  `-OC`, its low word under `-O2`. Never 0 for an RMS status.
  `PocRtl.mar`'s routines return longwords. `Platform` declares them
  `INTEGER`, since `SYSTEM.VAL` is not lowered yet.
- *`Directories`* (proposal 4, amended) is `rtl/vax/Directories.Mod`,
  `rtl/llvm/Directories.Mod` and, for Stage 0, `rtl/voc/Directories.Mod`.
  On VMS `IsDirectory` and `MakeDirectory` take a name that does not
  end in `:`, `]` or `>` as a logical name, and add the `:`, as
  `MakePath` does.
- *`$ERASE` checked.* `Unlink` of a file with two versions left
  `;1`, as proposal 3 expected.
- *`rtl/llvm`'s `Directories`* has `IsDirectory` and each `mkdir` in
  `Directories.c`, as `S_ISDIR` is a macro and `mode_t` is 16 bits on
  FreeBSD. `MakeDirectory` makes each missing level, as `mkdir -p`
  does. `rtl/voc`'s changes to the directory and back for
  `IsDirectory`, and runs `mkdir -p` for `MakeDirectory`.
- *`src/`* names its files through `Directories`: `MakePath` replaces
  the three `JoinPath` helpers and `Poc.Mod`'s and
  `VaxToolchainDriver`'s own joins, `IsDirectory` the two
  `Chdir`-and-back tests, and `MakeDirectory` the `mkdir -p` of
  `-output-dir` and of a library's directory, which is now reported
  when it fails. The import and library path lists split at
  `pathSeparator`. The joins left with `/` are the LLVM backend's
  library and run paths and the shell commands, none of them used on
  VMS.
- *The 39-character check* (proposal 3) is the 26-character limit
  section 5 already set for `<MODULE>_INIT`, stricter than ODS-2's 39.
  The driver now makes it as soon as a module is checked for the VAX,
  so it is reported as the checker's errors are and before the module's
  `.sym` is written, which on VMS would fail as a name RMS refuses
  (`vax-module-name-length`).
- *The default target* (proposal 7): `tools/build-info <dir>
  vax-dec-vms`, for a poc built to run on VMS, writes
  `BuildInfo.defaultTarget`, which `-target` is until one is given; that
  poc refuses any other ("not available on VAX/VMS"). Checked with such
  a poc built on Linux: `-build` with no `-target` writes the `.mar`
  files and the `.COM` procedure, and `-emit-llvm-ir` is refused as for
  `-target vax-dec-vms`.

**Done: `Files` (proposal 10's second part), 2026-10-10.**
`rtl/vax/Files.Mod`, over `PocRtl.mar`'s `POC_FILE_*` routines, with
the fixture `vax-files`, whose program prints the same on Linux and on
the guest.

- *Each File keeps its RMS blocks.* Its FAB, RAB, NAM block and XABFHC
  and its resultant name are in a 768-byte array in the File, which
  the routines get by reference, so no handle has to fit an `INTEGER`
  word under `-O2`. `PocRtl.mar` lays them out from STARLET's lengths
  and stops assembling if they outgrow it. A position goes by
  reference, a `LONGINT` whose low longword the routine reads, since a
  `LONGINT` will not become a longword under both size models.
- *Block I/O.* `$WRITE` keeps a sequential file's end at the highest
  byte written (RMS Reference, `$WRITE`), so the last block is written
  with its own byte count. On the guest odd counts work, and 41, 1300
  and 7 bytes come back exact. The length is the XABFHC's `(EBK - 1) *
  512 + FFB`.
- *`Register`.* `New` writes `POC_<pid>_<n>.TMP` in the directory of
  its name (the name is `$CREATE`'s default), and `Register` renames it
  with `$RENAME`. Given no version, the new name is a new version on
  the guest: a file registered twice is `;1` and `;2`. No temporary
  file is left.
- *Other record formats.* A variable-length file made by `CREATE` and a
  VFC one made by `OPEN/WRITE` read with an LF after each record. `Old`
  reads such a file through once to count its bytes, as `Length` must
  be the size of what `Read` gives: poc sizes a source's buffer by it.
- *Written only while new.* A file `Old` opens is never written, and a
  New one not after `Close`; either stops the program, as an error
  `Files` cannot report does (`POC_FILE_FAIL`, then `HALT(99)`).
- *`tools/vax-runtime-stub.mar`* has the same routines, so that the
  debugger runs link.

**Done: the collector (proposal 9), 2026-10-10.**
`rtl/vax/GarbageCollectedHeap.Mod` is `rtl/llvm`'s collector, ported
with its design and procedures, with the fixture `vax-collector`, whose
program prints the same on Linux and on the guest.

- *What it takes from the system* is in `PocRtl.mar`: memory from
  `LIB$GET_VM`, cleared (`POC_GET_MEMORY`), and given back by
  `LIB$FREE_VM` (`POC_FREE_MEMORY`), which needs the size, so each
  caller passes it; R2-R11 saved by an entry mask (`POC_SAVE_REGISTERS`,
  which then calls the stack scan); an exit handler (`POC_AT_EXIT`,
  `$DCLEXH`) for finalizing at exit; and the paging file quota left
  (`POC_PAGE_FILE_LEFT`, `JPI$_PAGFILCNT`). The heap's ceiling is three
  quarters of that when the collector starts. On the guest a heap grown
  until `NEW` gives `NIL` stops there, with the program still running.
- *`NEW` calls `Allocate`* by its symbol, with `POC_NEW`'s arguments, and
  `POC_NEW` is gone. `-build` adds the collector to a VAX program that
  calls `NEW`, as it adds `rtl/llvm`'s to an LLVM program, but alone:
  `ModuleTable` is not ported (proposal 1). `-emit-macro32` writes it
  only when the program imports it, so the fixtures with `NEW` review
  their own modules only.
- *Root tables.* A module whose variables hold pointers has `L_ROOTS`,
  laid out as `ModuleTable`'s tables are: a link, the count and the
  address of each pointer. Its initializer registers it with
  `POC_ROOTS`, in `PocRtl.mar` and so in every program, before its
  imports' initializers, and the collector reads the list from
  `POC_ROOT_TABLES`.
- *The program's start*, when the program calls `NEW`, calls the
  collector's initializer and then `SetStackBase` with its own `FP`,
  before the main module's initializer. Since 2026-10-28 (`PLAN.md`,
  "Ongoing bug fixing", 11) it does so too when the program has
  `GarbageCollectedHeap`, or a module from a library whose manifest says
  it allocates (`module <Module> <key> allocates`), as on LLVM.
- *`SYSTEM.ADR`, `GET`, `PUT` and `VAL`* are lowered, for the collector:
  an address in a register of its own, then a move of the variable's
  type or the value's; `VAL` retypes a value of its target's size or
  wider, and widens a narrower one, as on LLVM. `SYSTEM.PTR` is a
  longword. `SYSTEM.MOVE` is not lowered yet.
- *Conservative scanning keeps what a frame's slots still hold.* An
  argument list in a frame keeps the pointers passed in it until the
  slots are reused, so a list dropped in the frame that summed it
  survived a collection on the guest. The fixture drops it from a frame
  of its own. Whether this matters for poc is step 6's question.
- *`tools/vax-runtime-stub.mar`*, for the debugger runs, defines
  `Allocate`'s symbol, taking memory as `POC_NEW` did, and does nothing
  for the collector's initializer, `SetStackBase` and `POC_ROOTS`.

**Done: `POC.EXE` (proposal 10's end), 2026-10-10.** poc's own source,
with `rtl/vax` and a `BuildInfo` from `tools/build-info <dir>
vax-dec-vms`, builds with `-OC -build` on the host into 31 `.mar` files
and `Poc.com`, which assembles and links them on the guest into
`POC.EXE` (2,175 blocks) in about 40 seconds, transfers included. As a
foreign command it prints `-help`. The fixture `vax-poc` does this on
every `make test` with the guest.

- *Options without regard to case* (section 10; proposal 6) are built
  now: the first run printed `poc: unknown option -HELP`. In a poc built
  for VMS, an argument starting with `-` is lowercased before it is
  matched, but `-O2` and `-OC` keep their capitals, and so is the value
  of `-target`, a triple and not a name. Module and file names are not.
- *`-version`* on VMS leaves out the clang line, since that poc runs no
  clang (proposal 7).
- `vax-poc` compares `-HELP` and `-H` with what the host's poc prints
  for `-help`, so it needs no change when the help does, and
  `-VERSION` with the version and the commit the build used. Its guest
  procedure deletes the objects `POC.OPT` lists, so a module added to
  poc needs no change there either.

## 16. The test harness on VMS (Phase 16 step 5)

Step 5 runs the conformance fixtures' programs on the guest and compares
what they print with the LLVM backend's (`PLAN.md` Phase 16 step 5).
This section is the survey and the proposals, written for the user's
approval before any of it is done, as sections 14 and 15 were.
**Approved by the user, 2026-10-10, with (a) for proposal 5.**

**The survey (2026-10-10).** Of the 408 fixtures, 57 are `vax-*` ones,
which already run on the guest, and 206 build no program: they check
the lexer, the parser, the checker's messages, interfaces and the
documents, which run on VMS only once poc does (step 6). That leaves 145
whose `test.sh` builds a program and runs it. 23 of those test LLVM's
own features (IR text, clang, libraries, i686, `-lto`, `-g`, `-link`,
`-static`, C parts) and stay LLVM's. Each program of the other 122 was
built with `poc -target vax-dec-vms -import-path rtl/vax -build`:

| What stops it | Fixtures |
|---|---|
| nothing: it builds | 23 |
| an external `["C", "write"] SysWrite` (Phase 8's fixtures, written before `Out`), or another `["C"]` one | 45 |
| a module `rtl/vax` lacks: `Console` 10, `In` 3, `Strings` 2, `Math` 2, `MathL`, `Reals`, `Texts`, `Oberon`, `OutStr`, `VT100`, `ModuleTable` 1 each | 24 |
| a procedure `rtl/vax` lacks: `Modules.GetIntArg` 9, `Out.Real` 3, `Out.LongReal` 2, `Platform.FileHandle` 1, `Files.MaxPathLength` 1 | 16 |
| a construct not lowered: `LSH` 2, a structured constant 1, an imported pointer type 1, a `DSC$DESCRIPTOR` variable 1 | 5 |
| the survey could not find the program or its own modules (built in steps, from subdirectories) | 9 |

Each fixture is counted under its first program's first error, so a
fixture may need more than its row. The 23 that build:
`llvm-address-to-longint`, `-array-assign`, `-build-run`,
`-char-string-constants`, `-const-value-functions`,
`-declarations-after-procedures`, `-guard-assignment-target`,
`-hex-pattern-literals`, `-large-records`, `-long-short-width`,
`-long-strings`, `-module-init-order`, `-open-array-many-dimensions`,
`-ord-set`, `-overflow-wrap`, `-parameter-names`, `-set64`,
`-set64-import`, `-system-bytes`, `-system-int8-constants`,
`-system-new-trap`, `-var-initializers` and `-voc-library-fixes`.
`rtl/llvm`'s `FormattedText`, `ModuleTable`, `OutStr`, `RealDigits` and
`VT100` compile for the VAX as they are; its other modules call C.

A fixture's `expected` is its `result`: poc's own messages, which name
what poc wrote (`.ll`, `.o`, an executable) and so differ by target,
mixed with the program's output and exit status, and on some hosts
with lines a fixture writes itself. It cannot be compared with a guest
run as it is.

**Proposals.**

1. **A suite of its own, `make test-vax`**, run by `tools/vax-suite`,
   not by `make test`. It builds every program it lists on the host for
   the VAX, sends them all to the guest at once, runs one procedure
   there that assembles, links and runs each, and brings back what each
   printed: one transfer each way and one hold of the guest's lock, where
   a fixture each would take one of each per program, and would hold the
   lock against every other VAX fixture in a parallel `make test`.
   `make test` keeps the `vax-*` fixtures and `vax-poc`.
2. **A list, `test/vax-suite.list`**, one line a program: the fixture,
   its main module, the size model and the arguments it is run with.
   It starts with the 23 that build and grows as the rest are made to,
   rather than being found from each `test.sh`, which build their
   programs in too many ways.
3. **Compared with the same program built for the host**, in the same
   run: its standard output, its standard error and its exit status,
   each on its own, against the LLVM backend's build of the same source
   run here. That build is checked by the fixture's own `expected` in
   `make test`, so the suite checks the VAX against a checked program
   without reading `expected`. (`PLAN.md`'s "the same `expected` files"
   is met this way, since those files hold more than the program's
   output.) On the guest:
   - `SYS$OUTPUT` and `SYS$ERROR` go to two files (`DEFINE/USER_MODE`),
     compared separately, so their interleaving is not compared;
   - the status maps back to an exit code: `SS$_NORMAL` is 0, and
     `%X10000000 + 8*n + 2` is `n` (section 14, item 10);
   - arguments are passed quoted, so DCL keeps their case.
4. **A difference with a reason is written down, not skipped.** Where
   the VAX must print otherwise (a zero divisor: x86's `SIGFPE` against
   VAX's integer divide trap; a real's last digits in F or G floating),
   the fixture gets `expected-vax-<program>.out`, `.err` or `.status`,
   starting with `;;`-style lines saying why, for the user's review as an
   `expected-vax.mar` is, and the suite compares with that instead.
5. **The 45 `SysWrite` fixtures.** Either (a) their sources write with
   `Out` instead, the same characters with no line end, so that the
   LLVM output and `expected` stay the same and the VAX can run them;
   or (b) they stay LLVM's, since the `vax-*` fixtures of Phase 15
   already cover Phase 8's slice on the VAX. *Decided by the user,
   2026-10-10: (a)*, done as one mechanical change checked against each
   `expected`.
6. **What `rtl/vax` lacks stays Phase 17's** (its non-goals: libraries
   beyond what poc needs), but for two small ones that let 19 fixtures
   run: `Modules.GetIntArg` (9), and `Console` (10), written over
   `LineOutput` as `Out` is. `In`, `Strings`, `Math`, `MathL`, `Reals`,
   `Texts`, `Oberon`, `Out.Real` and the rest wait for Phase 17.
7. **The constructs not lowered** (`LSH`, structured constants, the
   other two) are lowered as the suite reaches them, each with a `vax-*`
   fixture and its reviewed `expected-vax.mar`, as in step 3.
8. **Order of work**: the suite and its list with the 23 (1-4); then
   `Modules.GetIntArg` and `Console` (6); then the `SysWrite` fixtures
   (5); then the constructs (7) and the 9 fixtures built in steps. The
   step ends when every listed program runs and matches, or differs
   only as an `expected-vax-<program>` file says, and the list holds
   every fixture of the 122 that `rtl/vax` and the backend can run.
9. **Both ways** (Phase 18 step 6d, `vax-object-language.md` section
   17.6): the suite builds every program twice, from this backend's
   MACRO-32 and from poc's own objects (`-vax-objects`), and checks
   both against the host's build; `VAX_WAYS=macro32` or `objects` runs
   one. A difference only objects have, a traceback naming each
   routine and line from its debugger records, is in
   `expected-vax-objects-<program>` files, looked for first.

**Done: the suite and its list (proposals 1-4), 2026-10-10.**
`tools/vax-suite`, run by `make test-vax`, and `test/vax-suite.list`,
with the 23 fixtures that built, each under the size models its
`test.sh` uses: 37 programs, and `vax-widen-and-new`'s. One run takes
about a minute, the guest's part one transfer each way.

- *Its first run* found four faults in the backend, fixed and covered
  by the new fixture `vax-widen-and-new`, whose `expected-vax.mar` was
  reviewed by the user (2026-10-10): `SHORT` of an `INT8` wrote `CVTBB`, which is no
  VAX instruction (now a move); `NEW` of more than 11 open dimensions
  skipped its length stores by a byte branch that could not reach (now
  over a `JMP L^`); a longword computed into R0 and returned as an
  `-OC` `LONGINT` kept R1 as it was (`MoveInto` did nothing for R0 into
  R0; now `ASHL #-31` fills it); and `SYSTEM.NEW` was lowered as `NEW`,
  its size ignored (now the block of that size, tag 0, trap 7 when the
  size is not positive, as on LLVM). No reviewed `.mar` changed.
- *A difference with a reason*: `llvm-overflow-wrap` divides 1.0 by
  0.0, an infinity on IEEE hardware and a floating divide by zero fault
  on the VAX, which has neither infinities nor NaNs. Its
  `expected-vax-overflow-O2` and `-OC` `.out`, `.err` and `.status`
  files, reviewed by the user (2026-10-10), say what the guest prints
  instead.
- *Code addresses* in VMS's own fault messages and tracebacks (`PC=`,
  `PSL=`, a traceback line's last two columns) are masked on the
  guest's standard output and standard error before they are compared,
  since any change to the code moves them.
- *A record has no "no line end"*: a host output whose last line has
  none is compared as if it had one.

**Done: `Modules.GetIntArg` and `Console` (proposal 6), 2026-10-10.**
`rtl/vax/Modules.Mod` gains `GetIntArg` and `ArgPos`, `rtl/llvm`'s, and
`rtl/vax/Console.Mod` is new: `rtl/llvm`'s interface over `LineOutput`,
into the same line as `Out`, so `Flush` does nothing. A list line now
takes poc options after the size model and the runs' arguments after
`:`, one run for each `;`-separated list. 18 lines join the list, from
10 fixtures: 57 programs, 157 runs.

- *The backend*: a `REAL` result moved into a `LONGREAL` in the same
  register (a function's `REAL` returned as a `LONGREAL`) was not
  converted (now `CVTFG` in place); and `-trap-heap-exhausted` was
  ignored (now `NEW` and `SYSTEM.NEW` test R0 after `Allocate`, trap
  11, as on LLVM). `vax-command-line`'s two `expected-vax` files change
  for `GetIntArg`, reviewed by the user (2026-10-10).
- *`rtl/vax`'s `Files`* made a `New` file on disk only when its block
  was written out, so a file that could not be created was not reported
  at the first `Write`, as `rtl/llvm`'s is; it now is.
  `vax-files`' `expected-vax-Files.mar` changes for it, reviewed by the
  user (2026-10-10).
- *Differences with a reason*, `expected-vax-*` files, as
  `llvm-overflow-wrap`'s: `ENTIER` of an infinity or a NaN
  (`llvm-entier-trap` cases 5 to 7) and `SHORT(1.0D300)`
  (`llvm-range-checks` case 0) are floating faults on the VAX; and
  `llvm-files-fail` names its file as given, not made absolute; they
  were reviewed by the user (2026-10-10). An
  `expected-vax-<module>[-<run>]` file without the build now serves
  every build that has none of its own.
- *Two things VMS does*, seen on the guest (2026-10-10): its message
  for a fault goes to the `SYS$OUTPUT` file too when the program has
  not yet opened it, so masking covers standard output as well; and its
  traceback names a routine only for a PC within about a kilobyte of
  its entry (907 bytes in, the routine; 1107, the program section), so
  under `-OC` two faults in a long module body name `POC_CODE`.
- *Not yet listed*, of the 19 fixtures proposal 6 counted: 9 need more
  than these two. `Files.Pos`, `Modules.ArgVector`, `Out.LongReal`,
  `Platform.Chdir` and `Platform.Absent` are Phase 17's;
  `llvm-console-extra` declares a `["C"]` procedure;
  `llvm-no-trap-behavior` uses `MOVE` (proposal 7); `llvm-trap-location`
  links a library its `test.sh` builds for the host.

**Done: the `SysWrite` fixtures (proposal 5), 2026-10-11.** 47
fixtures whose programs wrote through an external `["C", "write"]
SysWrite` write with `Out` now, the same characters, so each `expected`
stays as it was. A line end written as a character (`0AX`, `CHR(10)`)
is `Out.Ln` now, since on VMS it would land inside the record, an
extra blank line; comments that described `SysWrite` were changed with
the code. Six fixtures that declare it keep it: `llvm-var-record-params`
and `llvm-console-extra` test the C call itself, `llvm-sets-strings-ir`
compares IR, and `llvm-reject-external-vms`, `poc-exit-status` and
`poc-output-streams` test poc, not the program. `llvm-system-ir`, which
compiled `llvm-system`'s program to IR for two other triples, keeps a
copy of the program as it was, so its IR has none of the runtime's
declarations. 82 of the 84 programs build for the VAX and join the
list (139 programs, 239 runs); `llvm-gc-collect` needs `ModuleTable`
(Phase 17) and `llvm-system` `SYSTEM.VAL` from `ADDRESS` to `HUGEINT`
(proposal 7).

- *Differences with a reason*: `llvm-ash-max-min`, `llvm-const-fold`
  and `llvm-const-fold-import` check `MAX(REAL)` and `MAX(LONGREAL)`
  against IEEE 754's bounds, where the VAX's are F_floating's and
  G_floating's (section 14, item 9). Their `expected-vax-*.out` files
  were reviewed by the user (2026-10-11).
- *A front-end fault*: `llvm-reals` printed "FAIL 27" on the VAX.
  `ConstantEvaluator` folded a `REAL` expression in double precision
  (`SHORT(0.1D0) = 0.1` folded to `FALSE`), which the LLVM backend
  reached only in a `CONST` and the VAX backend, which folds an `IF`'s
  condition, here. Fixed on `main` (482375e, `PLAN.md`, "Ongoing bug
  fixing" 7) and merged (bf9c233).

**Done: `LSH`, `ROT` and `BIT` (proposal 7's first part), 2026-10-11.**
`VaxCodeGenerator` lowers the three at every width, each count a
constant or a variable of any integer type:
- `LSH` shares `ASH`'s count (`ShiftCount`, clamped to -64..64 for
  `ASHL`/`ASHQ`'s byte count). Left is `ASHL`/`ASHQ`; right, which the
  VAX has no logical shift for, is a shift right by 1, the sign bit
  cleared (`BICL2 #^X80000000` on the high longword), then the rest of
  the count. A `CHAR` or word is zero-extended first (`ZeroExtended`).
- `ROT` of a longword is `ROTL` by `n AND 31`, `n`'s floored modulo. A
  byte or word, which has no rotate, is multiplied by 2^w+1 to hold two
  copies, shifted left by `n AND (w-1)` and right by `w`. A `HUGEINT`
  calls `POC_ROTQ` (`rtl/vax/PocRtl.mar`): the halves exchanged for 32
  and more, each rotated by `ROTL`, and their low bits swapped through a
  mask.
- `BIT(a, n)` is `BBC n, (Ra)`, the VAX's variable bit field from the
  byte at `a`; a `HUGEINT` `n` adds its byte offset to `a` first.

The fixture `vax-shifts` has the reviewed `expected-vax.mar` and
`ShiftsOut`, which prints each case at each width on both backends; it,
`llvm-system-shifts` and `llvm-system-extra` join the list. So do three
fixtures that already built for the VAX but were not listed,
`llvm-hugeint-arithmetic`, `llvm-gc-finalize` (seven programs) and
`llvm-real-constant-folding`, whose `expected-vax-realfold.out`
records that `CVTLF` rounds 2^24+1 away
from zero where poc folds as IEEE 754 does (the user, 2026-10-11): 153
programs, 253 runs. That file and `vax-shifts`' `expected-vax.mar` were
reviewed by the user (2026-10-11).

**Done: `MOVE` and `VAL` into a `HUGEINT` (proposal 7's second part),
2026-10-11.**
- `SYSTEM.MOVE(a0, a1, n)` calls `POC_MOVE` (`rtl/vax/PocRtl.mar`)
  through `CALLG`, each argument a longword written straight into the
  list (a `HUGEINT` `n`'s low longword, as LLVM's on a 32-bit target).
  The routine does what LLVM's `memmove` does: nothing when `n <= 0`,
  and blocks that overlap as through a copy. `MOVC3` handles overlap
  but moves at most 65535 bytes, so a longer block goes in pieces, from
  the end when the destination is above the source. Fixture `vax-move`.
- `SYSTEM.VAL(HUGEINT, x)`, `x` narrower: the low longword `x` moved or
  widened, the high one its sign (`ASHL #-31`) for an integer, else 0,
  as LLVM's `sext` and `zext`. Fixture `vax-val`.

`vax-move`, `vax-val`, `llvm-system` (`-O2` only, as its `test.sh`:
under `-OC` its `LONGINT` is wider than the VAX's `ADDRESS`, which
cannot be assigned it) and `llvm-no-trap-behavior` join the list. Two of
the latter's cases differ, as their `expected-vax-notrap-*` files say: a `REAL` divided by zero is a floating
divide-by-zero fault (the VAX has no infinity), and a read at address 0
an access violation, VMS's `SIGSEGV`. Case 12, unbounded recursion, is
not run on the VAX: VMS's handler itself fails on the exhausted stack
and prints a register dump and stack contents, which vary. 158
programs, 278 runs. The user reviewed the `expected-vax*` files of
`vax-move`, `vax-val` and `llvm-no-trap-behavior` and `POC_MOVE`
(2026-10-11). `vax-emit-errors`' example of a construct not lowered,
`MOVE`, is now `SYSTEM.VAL` from a `HUGEINT` to a `REAL`.

**Done: structured constants (proposal 7's third part), 2026-10-11.** A
structured constant (Phase 14) is data in `POC_CONST`, `L_CONST_<n>`,
one for each value the module uses (an imported one too, from its
`.sym`), as LLVM makes a private constant global of each module that
uses one. Its bytes are a variable's, at `MemoryLayout`'s offsets, the
padding and the elements not given zero; a scalar is `.BYTE`, `.WORD`
or `.LONG`, a quadword two `.LONG`s, a real `.F_FLOATING` or
`.G_FLOATING` of `RealConstant`'s text. It is used as a variable is:
copied to assign, its address passed. Record and array literals that
are not constant are still not lowered. Fixture
`vax-structured-constants`, run under `-O2` and `-OC`.

`llvm-readonly-params` joins the list too, under both size models, its
fourth line an `expected-vax-readonly.out`: `First16`'s read-only `ARRAY 16 OF CHAR` is passed by reference
on the VAX, which passes every read-only record or array so (section 7,
decided 2026-10-06), and by value on LLVM, which passes one of at most
16 bytes so; a program may not rely on which. 162 programs, 282 runs. The user
reviewed it and `vax-structured-constants`' `expected-vax.mar`
(2026-10-11).

**Done: record field initializers (proposal 7's fourth part),
2026-10-11.** `llvm-extension-through-pointers` was held back not by its
pointers but by a field initializer (`language-extensions.md`, "Record
field initializers"), which the VAX backend refused with every type that
reached one. It now lowers them as LLVM does:
- Each record type with defaults has an initialization procedure,
  `<Module>.<path>.-init` through `VaxTypes.MakeSymbol`, called with the
  record's address (`PUSHL`, `CALLS #1`): its base type's procedure
  first, then each field with a default assigned it (`AssignTo`, split
  out of `Assignment`), in the scope the record was declared in, and
  each field holding records with defaults given them. A record the
  front end named (`initPath`) has `.ENTRY`, which another module calls
  through `G^`; any other, `-anon<n>`, is private, a label and `.WORD`
  mask. The module defines them after its procedures and again after
  its body, which can ask for more (`InitProcedures`).
- They are called where a record is made: module variables and locals,
  in declaration order with the variable initializers
  (`DeclarationInits`); `NEW` of a record, of a fixed array and of an
  open array, once the pointer holds the block and not when there is
  none. An array of records is a loop, its address and count in two
  pinned registers from R2, which a call keeps.

Fixture `vax-field-initializers`, three modules, under `-O2` and `-OC`;
it and `llvm-extension-through-pointers` join the list
(`llvm-field-initializers` waits for `Out.Real`, Phase 17): 166
programs, 286 runs. The user reviewed the fixture's `expected-vax.mar`
and `expected-vax-VaxFields.mar` (2026-10-11). Found on the way: a comment in the code list was
cut to 31 characters, so two procedures' titles in `vax-collector`'s
`expected-vax-GarbageCollectedHeap.mar` were cut too; comments now keep
their length. `vax-emit-errors`' examples of what is not lowered, an
array of records with a default and a pointer to one, are now a record
literal that is not constant and `SYSTEM.VAL` from a `REAL` to a
`SET64`.

**Done: proposal 7's last fixture, 2026-10-11.** `llvm-underscore-dollar`
was held back by a variable of the imported `Ss$Def.DSC$DESCRIPTOR`,
which has a field with a default (`$init`, named like the backend's own
names); field initializers lowered, it runs on the guest under both size
models as it is and joins the list: 168 programs, 288 runs. Every
construct the survey found unlowered (`LSH`, `ROT`, `BIT`, `MOVE`,
`SYSTEM.VAL` into a `HUGEINT`, structured constants, field initializers)
is lowered now; record and array literals that are not constant, and
`SYSTEM.VAL` between a real and a type of another size, are not, and no
listed fixture needs them. What remains of step 5 is the 9 fixtures
built in steps.

**Done: the 9 fixtures built in steps (proposal 8), 2026-10-11.** The
survey could not find their programs because each `test.sh` builds in
steps: in work directories, from subdirectories, with `-compile` first.
`tools/vax-suite` now builds a list line's main module that is in a
subdirectory (`src/M.Mod`) from that directory, so its own modules are
found beside it and a relative `-import-path` is relative to it. Of the
nine:

- *Four join the list*, their programs as their `test.sh` runs them:
  `llvm-trap-location` (`-import-path lib -trap-location
  -trap-heap-exhausted`, all 16 cases under both size models, and case
  0 without `-trap-location`), `llvm-gc-compiled-roots` (`M`, whose `G`
  holds what a collection must keep, and `N`), `llvm-using-modules`
  (`main`, `app`, and the other `app` with `-import-path ../src`) and
  `semantic-strict-compiled-imports` (its `client` and the new
  `uselocals`, under `-strict`). Built here from source, not from a
  `.sym` and `.o` compiled first, a library or an object's weak
  references: those are the LLVM driver's, and stay in their fixtures.
- *Five stay the LLVM driver's or poc's own*: `llvm-module-keys` (the
  key symbols that make an object link only with the interface it was
  compiled against), `llvm-object-reuse` (clang's objects reused by
  their stamps, with a C part), `poc-opt-level` (clang's `-O`), and
  `poc-exit-status` and `poc-output-streams` (poc's own status and
  streams, which run on VMS when poc does, step 6).

Found on the way, and fixed:
- Under `-strict`, an import compiled from source with a `HUGEINT`
  among a procedure's locals was an error, named with the importer's
  file, on both backends: the checker turns `-strict` off for an import,
  but each backend reopens a procedure's body to generate it
  (`SemanticActions.OpenProcedureBodyScope`), which resolved the locals
  again with it on. `rtl/vax`'s `LineOutput` has such locals, so every
  `-strict` program that wrote with `Out` failed for the VAX. Reopening
  a body now reports nothing under `-strict`; fixed on `main` too, and
  `semantic-strict-compiled-imports` has the case (`uselocals`, not
  `locals`, which VMS would not tell from `Locals`).
- The VAX's trap 9, an open array too long for the fixed array assigned
  it, named the value's column (`a` in `t := a`), LLVM's the
  assignment's; it is the assignment's now (`AssignTo` takes the
  position), which changes two lines of `vax-open-arrays`'
  `expected-vax.mar` and its debugger run's column.

178 programs, 328 runs: the list holds every fixture of the 122 that
`rtl/vax` and the backend can run, so step 5's list is complete (a
sweep of the rest found none that builds). The others need what
`rtl/vax` lacks (`Out.Real`, `Modules.Halt`, `In`, `Strings`, `Math` and
the rest: Phase 17), a `["C"]` external, or a record or array literal
that is not constant, which the backend does not lower yet.

## 17. Bootstrapping on VAX/VMS (Phase 16 step 6)

Step 6 builds poc for VAX/VMS in stages (`PLAN.md` Phase 16 step 6):
V1, the host's poc cross-compiling poc's source, assembled and linked on
the guest into `POC.EXE`; V2, that `POC.EXE` compiling the same source
on VMS, its `.mar` the same as V1's; V3, V2's image doing it again.

**The first runs (2026-10-11).** V1 is what `vax-poc` already builds.
`POC.EXE`, run on the guest from a directory holding poc's sources and
`rtl/vax`'s side by side (VMS directory names in the import path are
not split yet, section 15), found two faults in the backend, each
fixed with the fixture beside it:

- *A wide element or field at offset 0 of a parameter reached by its
  address.* `hash[0] := 25H`, `hash` a `VAR ARRAY 8 OF LONGINT` (a
  quadword under `-OC`), was `MOVL #^X25, @4(AP)` and `CLRL @8(AP)`:
  element 0 kept the parameter's deferred operand, and its high
  longword added 4 to the displacement, the next argument's target. No
  operand names 4 bytes past the target of `@4(AP)`, so `Displace` now
  rebases a deferred operand for a quadword or `G_floating` element or
  field at offset 0 too. `POC.EXE` died with an access violation at its
  first `.sym` (`ModuleInterface.HashStart`). Fixture
  `vax-deferred-wide`.
- *A quadword sum into a destination that its second operand may
  overlap.* `r[i + j] := r[i + j] + p` moved `p` into `r[i + j]`,
  through one register, and then added `r[i + j]`, through another, to
  itself. `QuadAddSub` and `QuadSet` now write into the destination
  first only when the second operand cannot overlap it
  (`WritableBefore`: not in memory, the same operand, or a variable or
  slot named apart from it), else they go through a register pair.
  Every mangled name's hash (`VaxTypes.AppendHash`) was wrong, so the
  `.mar` `POC.EXE` wrote named other symbols than the host's. This
  changes `vax-arrays'`, `vax-nested'` and `vax-parameters'`
  `expected-vax.mar` and one debugger log. The user reviewed them and
  `vax-deferred-wide`'s `expected-vax.mar` (2026-10-11).

With both fixed, `POC.EXE` compiles `hello` (with `Out`) and poc's own
`Lexer` (with `LineOutput`, `Err` and `Diagnostics`) on the guest to
`.mar` byte-identical to the host's: `Lexer` in 10 s, 8 s of CPU, and
`-build` of `hello` makes a program that runs.

**Memory.** `VaxCodeGenerator` alone, and all of poc with `-build`,
stop in `NEW` (`-trap-heap-exhausted`: "heap exhausted" in
`SemanticActions.NewDesignator`) at about 12,000 pages of virtual
memory: the heap's ceiling is three quarters of the paging file quota
left at the start (section 15), about 7,200 pages (3.6 MB) of `POC`'s
10,240. On the host the same compilations for the VAX need 63 MB
(`VaxCodeGenerator`) and 112 MB (all of poc, `-build`) of resident
memory on x86-64; step 1 measured 105 MB for all of poc on 32-bit
OpenBSD. The guest has 64 MB of memory (131,072 pages; step 1 recorded
256 MB), `VIRTUALPAGECNT` 139,072 pages (68 MB), `WSMAX` 32,800, and a
paging file of 139,096 blocks (68 MB; 109,661 reservable).

**Decided (the user, 2026-10-11): the guest's limits are raised**,
reversing step 1's decision that poc must fit them, so that the fixed
point can be reached; making poc need less is later work, recorded in
`PLAN.md`. What it needs, with room for the collector's three quarters:
a `PGFLQUOTA` for `POC` of about 300,000 pages (150 MB), a
`VIRTUALPAGECNT` above that, a paging file to hold it, and a larger
working set (`WSQUOTA`, `WSEXTENT`, within `WSMAX`) so that poc does not
page on every allocation; and the memory SIMH gives the VAX back to 256
MB. These are privileged changes the user makes on the guest.

**Done: the guest's limits raised (the user, 2026-10-11).** The VAX
has 256 MB again (524,288 pages), `VIRTUALPAGECNT` is 350,000,
`PAGEFILE.SYS` 350,000 blocks, and `POC`'s `PGFLQUOTA` 300,000 pages,
`WSQUOTA` 8,192 and `WSEXTENT` 16,384. (Raised since: on 2026-10-20
`AUTHORIZE` showed `WSQUOTA` 32,768 and `WSEXTENT` 200,000, and
`SYSGEN` `VIRTUALPAGECNT` 600,000; `POC2` has the same quotas as `POC`
since 2026-10-19.)

**Real constants when poc runs on the VAX.** All of poc then got as far
as its 15th module and stopped on a floating overflow: every real
constant the VAX backend writes is compared with IEEE 754's largest of
its type (`RealConstant`), and poc folds real constants in its own
`LONGREAL`, which on the VAX is `G_floating`, whose largest is half
IEEE's: `ConstantEvaluator.MaxLongReal` computed `2^1023`, beyond it.
**Decided (the user, 2026-10-11): a poc running on the VAX folds in
`G_floating`.** `ConstantEvaluator.vaxHost`, set by `Poc.Mod` from
`BuildInfo.defaultTarget`, makes `MAX` and `MIN` of `REAL` and
`LONGREAL` the VAX's own largest values (built from powers of two that
fit), which are what the VAX target writes for them anyway, and
`RealConstant` compares with those directly; the `.mar` is the host's.
Every other real constant is folded in the host's arithmetic, so on the
VAX one beyond `G_floating`'s range traps (a floating overflow) instead
of being reported, and a rounding tie may fold differently in its last
bit (the VAX rounds ties away from zero). Making the folding IEEE in
software on every host is later work.

**Done: V2 (2026-10-12).** `POC.EXE`, cross-compiled from this tree and
linked on the guest (V1), compiled all of poc on VMS with `-OC -target
vax-dec-vms -build POC.MOD`, from one directory holding poc's sources,
`rtl/vax`'s and `BuildInfo.Mod`: 45.7 minutes, 1,060 s of CPU, a peak of
184,516 pages (90 MB) of virtual memory. All 31 `.mar` files are
byte-identical to V1's; `POC.COM` differs only in its first line, which
names the source file as given (`POC.MOD`, the host's full path). A
`POC.EXE` built from the current tree is kept in `DUA1:[USERS.POC.BIN]`
for the user (`POC :== $DUA1:[USERS.POC.BIN]POC.EXE`).

**Done: V3 (2026-10-12).** One procedure on the guest, from commit
`752a676`: V1's `.mar`, the host's, assembled and linked; V1's
`POC.EXE` compiling poc (44.8 minutes, 991 s of CPU), its `.mar`
assembled and linked into V2's `POC.EXE`; and V2's image compiling poc
again (45.1 minutes, 987 s), its `.mar` linked too. All 31 of V3's
`.mar` are byte-identical to V2's and to V1's: the fixed point holds on
VMS itself.

**Done: the scripts (2026-10-12).** `tools/bootstrap/vax-v1` is V1:
the host's poc cross-compiles poc's source, with `rtl/vax` and a VMS
`BuildInfo`, into `build/vax-bootstrap/v1`. `tools/bootstrap/vax-stages
[-to v1|v2|v3] [-install] [-keep]` runs it, then sends V1's `.mar` and
`Poc.com`, poc's sources, `rtl/vax`'s and `BuildInfo.Mod` to the guest
in one transfer. There one procedure it writes, `VAXBOOT.COM`, runs each
stage in its own directory under `[.BOOTSTRAP]`:
- it links a stage's image only when the next stage runs it, or with
  `-install`, which copies the last one to `[.BIN]POC.EXE`;
- it logs each compilation's elapsed time, CPU time and the process's
  peak virtual memory;
- it copies V2's and V3's `.mar` and `POC.COM` back as
  `V<n><MODULE>.MAR`.

The script compares those files with V1's (`POC.COM` after its first
line) and checks that each stage wrote as many `.mar` files. Its
removal of `[.BOOTSTRAP]` uses one `F$SEARCH` per wildcard spec, since a
second call with the same spec continues the first call's search: the
first try kept the directory that way. The first full run, from this
tree: V2 in 45.7 minutes (985 s of CPU), V3 in 46.0 (997 s), a peak of
184,516 pages, and all 31 `.mar` of both identical to V1's. What step 6
still asks for: the conformance suite under the compiler built on VMS.

**The suite under the compiler built on VMS: survey (2026-10-12).** The
fixtures that could run under a poc on VMS, by what they do:

| What it does | Fixtures | How it compares |
|---|---|---|
| builds a program, listed in `test/vax-suite.list` | 178 programs | its run on the guest with the LLVM build's (step 5) |
| `vax_mar <Module> [<option>...]`: poc `-emit-macro32` | 56 `vax-*` | each `.mar` with an `expected-vax*.mar` |
| only `poc [-strict] [-O2\|-OC] -check <file>`, one or more | 115 | `result` (messages and exit status) with `expected` |
| poc's own commands, nothing else (debug dumps, `-emit-interface`, `-show-interface`, `-output-dir`) | 30 | `result` with `expected` |
| poc's commands in a script (loops, `sed`, `cmp`) | 17 | as the script does |
| the LLVM driver, clang, voc, the documents, another target, or poc's own help and version | 23, and the other 8 `vax-*` | stay the host's |

Messages name a source file as poc was given it, so a guest run must
give it in the same case. A fixture whose expected output depends on the
target (`ADDRESS`'s width, the default size model) differs on the VAX
without anything being wrong.

**Proposals.**

1. **The compiler: V1's image, linked at the start of each run.** V2's
   `.mar` are V1's, assembled and linked by the same `MACRO` and `LINK`,
   so V1's `POC.EXE` is the image V2's would be; `vax-stages` is what
   checks that, in 90 minutes. Linking costs about a minute, and the run
   then depends on nothing left on the guest (not `[.BIN]POC.EXE`).
2. **Compared with the host's poc for the VAX.** Each command runs on
   the guest as the host would run it with `-target vax-dec-vms`; what
   the guest's poc prints, its exit status, and every text file it
   writes (`.mar`, `.sym`, the build procedure after its first line)
   must be the host's. The reference is made in the same run, as
   `vax-suite`'s LLVM builds are, so no fixture needs an expected file
   of its own for this, and the target-dependent fixtures need none.
3. **Three groups, one tool**, `tools/vax-guest-poc` (`make
   test-vax-guest-poc`), one `vax-do` run:
   - (a) *the 178 programs*: each compiled with `-build` on the guest,
     its files compared with the host's. They are not linked or run
     again: identical `.mar` make identical programs, and step 5 ran
     them.
   - (b) *the 56 `vax_mar` fixtures*: `-emit-macro32` with the
     fixture's options; each `.mar` is compared with the host's (and so
     with `expected-vax*.mar`, which `make test` checks).
   - (c) *the 115 `-check` fixtures*: found from `test.sh` by that one
     pattern, so a new one joins by itself; messages and exit status
     compared with the host's.
   The 30 plain and 17 scripted ones join later, through a list as (a)
   has, once (a)-(c) pass; the 31 that stay the host's are named in the
   tool with the reason for each.
4. **Each in a directory of its own** on the guest, under
   `[.GUESTPOC]`, holding the fixture's sources, so that two fixtures'
   modules of one name cannot meet; `rtl/vax` is sent once and found
   through `POC_IMPORT_PATH`, a logical name (section 15, proposal 5;
   `POC$IMPORT` since 2026-10-12).
   A source is named on the command line quoted, in the case the
   fixture uses.
5. **Its cost.** poc compiles `Lexer` on the guest in 10 seconds; a
   fixture's module is far smaller, but each run starts a 2,175-block
   image. About 350 compilations should take well under an hour, all in
   one hold of the guest's lock. Not part of `make check`.

**Approved by the user, 2026-10-12.**

**Done: `tools/vax-guest-poc` (2026-10-12).** `make test-vax-guest-poc`
runs proposals 1-5 as written: 344 items (182 programs, 57 `vax_mar`
lines, 105 `-check` fixtures; `-only <regex>` keeps some), about 35
minutes. Each item's files come back in one file, `RESULTS.TXT`, which
`APPEND` builds on the guest. `APPEND` warns that poc's files and it
have other record attributes (`APPEND-W-INCOMPAT`) but copies the
records, so its messages are turned off and only an error is reported.
Three things the proposals did not foresee:
- *File names in `-trap-location`'s strings.* A program built with it
  names each source file as poc found it, `/home/.../rtl/vax/Out.Mod`
  on the host and `DUA1:[USERS.POC.GUESTPOC.RTL]Out.mod` on the guest,
  `lib/traplib.mod` and `[.LIB]traplib.mod`. The tool compares those
  strings as names: rtl/vax's directory as `<rtl>/`, a VMS directory as
  a relative Unix one, in lowercase.
- *A file name VMS cannot hold.* An item whose source has one (a name
  or type past ODS-2's 39 characters) is reported as left out, not
  failed. The one there was, `semantic-decl-order-const-refs-later-
  section-type`'s 40-character source, is now `later-section-type.mod`
  (the user, 2026-10-12).
- *A difference the VAX must have.* A fixture's
  `expected-vax-guest-<key>.diff` (`<key>` the main module and the
  list's options, as `vax-suite`'s, or the `vax_mar` module, or
  `check`) is the whole difference the item may show, its lines
  starting `;;` saying why.

Its first run, 329 of 341 passing, found two faults in poc running on
the VAX, both fixed:
- *A register moved on one path of an `&` or `OR`.* `ShortCircuit`
  spilled every register in use before its left side, but not a pinned
  one, a field's base, which a call on the right side's path then moved
  out of R0 (`FreeR0R1`) on that path only: the store after the join
  went through a stale register when the left side decided.
  `MethodCallTarget`'s `m.fromParam := ~m.fromBlock & (real = NIL) &
  (ParamTag(obj) # NIL)` overwrote the local `method` that way, and
  every type-bound call through a pointer with a second procedure failed
  (`llvm-type-bound`, `vax-type-bound`). Found by printing from poc on
  the guest. `ShortCircuit` now moves a pinned register out of R0 and R1
  before its left side, except an enclosing `&` or `OR`'s left side,
  which that one brings back at its own join. Fixture
  `vax-short-circuit-call`, whose `expected-vax.mar` the user reviewed
  (2026-10-12); no other fixture's `.mar` changes.
- *`MAX(LONGREAL)` written on the VAX.* `ModuleInterface.FormatReal`
  looks for the shortest text that parses back to its value, and for
  the VAX's largest a candidate rounded up past it overflowed in
  `DecimalToDouble` (a floating overflow on the guest; infinity, and
  the search goes on, on IEEE). `DecimalToDouble.ParseWithin` now says
  that a numeral is beyond a binary exponent without computing it, and
  `ConstantEvaluator.ParseRealInRange` uses it with G_floating's (970)
  on a VAX host, IEEE's (971) elsewhere (`llvm-ash-max-min`,
  `llvm-const-fold`, `llvm-const-fold-import`).

The second run: 341 passed, the long file name was left out (since
renamed, and passing), and the 2 builds of `llvm-real-constant-folding`
differ as their `expected-vax-guest-realfold-*.diff` say, reviewed by
the user (2026-10-12): a halfway case folds by the VAX's own rounding,
the limitation the user accepted (2026-10-11). So all 344 pass.


## 18. Libraries on VAX/VMS (Phase 17 step 1)

Step 1 works out how poc builds a library for VAX/VMS, static and
dynamic, and how a program links against one (`PLAN.md` Phase 17 step
1). This section is the survey and the proposals, written for the
user's approval before any code, as sections 13-17 were.

**Sources.** The *VMS Linker Utility Manual* (`AA-LA62A`, 5.0, April
1988; no later revision exists, `vax-vms-manuals-to-get.md`): chapter 3
(options: `UNIVERSAL=`, `GSMATCH=`, `CLUSTER=`, `PSECT_ATTR=`), chapter
4 (shareable images), 6.3.6.2 (the fix-up image section) and chapter 7
(the object language, `TIR$C_STO_PICR` and `TIR$C_STQ_PIDR`). The *VMS
Librarian Utility Manual* (`AA-LA61A`, 5.0). The *VAX MACRO and
Instruction Set Reference Manual* (`AA-LA89B`, 5.4), `.PSECT`. Checked
against the *VMS Version 5.5 Release Notes* (`AA-LB22D`, section 3.17),
the *VMS Version 5.5 New Features Manual* (`AA-LA97D`, section 19.1) and
the *VMS Version 5.5-2 Release Notes* (`AV-PQZAB`): the only Linker
changes are the `CASE_SENSITIVE=` option (5.5), `MULSHRPSC` (5.5, below)
and a debugger-symbol fix (5.5-2). Nothing in them changes shareable
images, transfer vectors or `GSMATCH`. (The linker's `SYMBOL_VECTOR=`
option, often cited for shareable images, is OpenVMS AXP's and does not
exist on VAX 5.5-2.)

### 18.1 What the manuals fix

- **An object library** (`LIBRARY/CREATE/OBJECT`, `.OLB`) indexes its
  modules by module name (MACRO's `.TITLE`) and by every global symbol
  they define, case kept (Librarian, sections 2-3). `LINK prog,
  lib/LIBRARY` takes a module from it only to resolve a symbol still
  undefined. `LIBRARY/INSERT` refuses a module whose name *or global
  symbol* is already in the library ("an error message is issued and the
  module or symbol is not added", Librarian, `/INSERT`), which answers
  section 5.1's question about `DUPGLOBAL` from the manual; it still sees
  one library only. `/REPLACE` (the default) replaces a module of the
  same name.
- **A shareable image** is made by `LINK/SHAREABLE` from object modules
  and, optionally, other shareable images (Linker 4.3), and is used by
  naming it in an options file, `NAME/SHAREABLE`, or through a
  shareable-image library (`LIBRARY/CREATE/SHARE`, Librarian section 4).
  Only its **universal** symbols are visible to what links with it,
  made so by `UNIVERSAL=` or MACRO's `.TRANSFER` (4.3.1); an absolute
  symbol can be universal too ("sometimes other constants").
- **Position independence** (4.2.2). Inside the image, PC-relative
  references; to a target outside it, general mode, `G^`. MACRO writes a
  `G^` operand as `TIR$C_STO_PICR`: the linker makes it relative when
  the target is in the image being linked and *relative deferred through
  a fix-up cell* when the target is in another shareable image (chapter
  7, command 28), for a data operand as for a call. `.ADDRESS` is
  relocated by the image activator from the fix-up image section
  (6.3.6.2); `.LONG` of a relocatable address makes the image
  position-dependent and draws a linker warning.
- **Sharing between processes** (4.2.1). Sections with `WRT` and
  `NOSHR` become copy-on-reference: each process its own copy, which is
  what Oberon's module variables need. A section that holds an
  `.ADDRESS` "is not shareable", since the activator writes into it.
- **Finding the image at run time** (4.4). The activator takes the file
  name from the image's global section name and looks for
  `SYS$SHARE:<name>.EXE`, unless a logical name `<name>` says where it
  is: `DEFINE LBRSHR DISK$WORK:[MYDIR]LBRSHR`. An image that is not
  installed is mapped as a private copy, which needs no privilege; only
  sharing the physical pages needs `INSTALL`, a privileged command, so
  the unprivileged user `POC` can use shareable images without it.
- **Versions** (3.3, `GSMATCH=`). The image header carries a match
  keyword and a major and minor id, copied into each executable linked
  with it; at activation the major ids must be equal and the minor ids
  must satisfy `EQUAL`, `LEQUAL` or `ALWAYS`, else the activator refuses
  with a message that the program must be relinked. With no `GSMATCH=`
  the ids come from the image's creation time, so any relink of the
  shareable image forces a relink of its users.
- **Upward compatibility** (4.2.3-4.2.4) comes from transfer vectors:
  `.TRANSFER`/`.MASK`/`JMP L^routine+2`, eight bytes each, in one module
  linked first, never reordered. They cover *routines* only; a universal
  data symbol has the address its section gave it in this link.
- **`MULSHRPSC`** (5.5 Release Notes 3.17.2). The 5.5 linker refuses two
  shareable images that define the same *global* program section. poc's
  sections are local: `LCL` is `.PSECT`'s default (MACRO, Table 6-7) and
  poc writes no `GBL`, so every module's `POC_CODE`, `POC_CONST` and
  `POC_DATA` stay in their own image.

### 18.2 What poc already has

Most of what a shareable image needs was decided for other reasons in
Phase 15:

- Every reference to another module is `G^` (section 7, `vax-modules`):
  variables, procedures, an element through an index (`G^X[R1]`) and a
  field through an offset (`G^X+2`) alike. So code compiled once links
  unchanged against a module in the same image, an object library, or
  another shareable image.
- `POC_CODE` and `POC_CONST` are `PIC,SHR,NOWRT`, `POC_DATA` is
  `NOPIC,NOSHR,WRT`: per-process module variables.
- Symbols are a function of the full name alone (section 5), so they
  are the same whatever else is in a library, and each module defines
  `POC_K1_<key>` (section 5.1), which its importers name.
- The collector finds module variables through root tables that each
  module's initializer registers (`POC_ROOTS`, section 15), not through
  section bounds, so roots in several images are found.
- What does not fit: type descriptors, method tables and the
  runtime's tables of addresses are `.ADDRESS` lines in `POC_CONST`
  (90 in the fixtures' `.mar`), and no `-library` for the VAX target.

### 18.3 Proposals

**Approved by the user, 2026-10-12**, all eight as written: object
libraries by default (1), relink on every relink (3) and a
`<NAME>_SETUP.COM` per library (6) included.

1. **Two kinds, as on LLVM.** `poc -target vax-dec-vms -library <name>
   <modules>` makes a library as Phase 12 does (`Libraries.Mod`: the
   manifest, `.sym`, `<Module>.owner`), with the VAX's files in place of
   the archive and the shared library: `<NAME>.OLB`, an object library of
   the modules' objects, and `<NAME>.EXE`, a shareable image of the same
   modules. As with `-build`, the host writes the `.mar` and a DCL
   procedure, `<NAME>.COM`, that assembles them and runs `LIBRARY` and
   `LINK` on VMS; poc on the guest does the same. A program links the
   object libraries by default, the shareable images when asked (the
   reverse of LLVM's default, since an image found by logical name needs
   setting up, proposal 6; to be settled with the user). No layered
   product: DCL, not MMS, as decided on 2026-10-09 (Phase 16 step 1);
   step 1's "the build descriptions are MMS ones" in `PLAN.md` changes to
   match.
2. **What a shareable image exports.** `UNIVERSAL=` for every symbol an
   importer can name: each exported variable and procedure, each type
   descriptor and the tables beside it that an importer's code refers
   to, `<MODULE>_INIT`, and `POC_K1_<key>`.
   poc writes the options file from what it knows of each module; it
   never relies on the linker to guess. Psects stay local (18.1,
   `MULSHRPSC`).
3. **Versions: relink on every relink, for now.** No `GSMATCH=`, so a
   program must be relinked whenever a shareable image it uses is, and
   the activator says so if it is not. Transfer vectors would spare
   that for procedures only: an exported variable or type descriptor
   moves with any change to the module's data, which no vector covers.
   Holding the data's layout too (exported data first, in `.sym` order,
   in a section clustered ahead of the rest, plus vectors and
   `GSMATCH=LEQUAL`) is possible later if the user wants upward
   compatibility. The interface check stays where it is: an importer
   compiled against another `.sym` fails at link time on `POC_K1_<key>`
   (`%LINK-W-NUDFSYMS`, which the build procedure treats as fatal).
4. **One runtime and one copy of each module per process.** The runtime
   (`POCRTL.MAR` and `rtl/vax`'s modules) becomes a library itself,
   `POCRTL` (`.OLB` and `.EXE`), as `poc-rtl` is on LLVM. A shareable
   library is linked against the shareable images of the libraries it
   needs, `POCRTL` included, never against their objects: two images
   with their own copy of the collector would each run one heap. A
   program links either every library's object library or every
   library's shareable image, not a mixture, so that no module is in the
   program twice; poc checks it from the manifests, as Phase 12 does.
5. **Addresses out of the shared constants.** A new section,
   `POC_ADDR` (`PIC,NOSHR,NOWRT,NOEXE,LONG`), takes every constant that
   holds an `.ADDRESS` (type descriptors and their tables, the
   runtime's tables of addresses), so that `POC_CODE` and `POC_CONST`
   can be shared between processes when an image is installed (18.1).
   It changes many fixtures' `expected-vax.mar` (a `.PSECT` line before
   each descriptor), each to be reviewed as usual; behavior does not
   change.
6. **Finding libraries.** At compile time, as on LLVM: `-library-path`,
   then the logical name `POC$LIBRARY` (a search list) on VMS in place of
   `POC_LIBRARY_PATH`, then `<poc's directory>/../lib/poc`, each with
   its tuple directory; on VMS the joins are `Directories`' (section 15),
   which gains a subdirectory join (`[A]` and `B` give `[A.B]`).
   Whether `VAX-DEC-VMS` is a usable directory name (the hyphen) is to be
   checked on the guest; if not, the VMS tuple directory is
   `[.VAX_DEC_VMS.<O2|OC>]`. At run time, the activator's way (18.1): a
   logical name `<NAME>` for each library's image. A library's
   directory gets a `<NAME>_SETUP.COM` that defines them (the library's
   and those it needs), which a user runs once a session, or puts in
   `LOGIN.COM`, as VMS products do; a program's build procedure runs it
   for its own test run.
7. **Collisions across libraries** (section 5.1, layer 2), now that
   modules are compiled apart: at `-library` and at a program's link,
   poc recomputes each symbol of the import closure from the `.sym`
   files and stops on two full names with one symbol. The Librarian
   (18.1) catches one within one library; this catches the rest.
8. **Testing.** A fixture with a small library of three dependent
   modules, built both ways; a program linked against each and run on
   the guest; and the failure cases, each a message rather than a crash:
   an importer compiled against a different `.sym` (link time,
   `NUDFSYMS`), a missing image (activation), a relinked image under an
   old program (`GSMATCH`). Before any of that, a hand-written check on
   the guest that the facts above hold for poc's code: a `G^` data
   reference, an indexed one and one with an offset into another
   shareable image; a type descriptor's `.ADDRESS` in a `NOWRT` section
   of a shareable image; and the hyphen in a directory name.

### 18.4 Checked on the development system (2026-10-12)

A hand-written shareable image `SHRLIB` in poc's sections - variables
in `POC_DATA`, a two-address "descriptor" in `POC_CONST` as poc writes
one now and another in a `POC_ADDR` as proposal 5 has it, two routines
and a `POC_K1_` key, all `UNIVERSAL=` - and a program `SHRMAIN` that
links it as `SHRLIB.EXE/SHAREABLE` and reaches it only by `G^`, the
image found through the logical name `SHRLIB`:

- *Everything resolves.* `SHRMAIN`'s nine checks pass: a variable, an
  indexed element (`G^SHR_T[R1]`), a field at an offset (`G^SHR_R+4`),
  two calls, a variable the image itself changed (one copy, the
  image's), both descriptors' `.ADDRESS` of a variable as `MOVAB G^`
  gives it, a routine's address as the program and the image see it, and
  a call through the descriptor. Linked with no messages.
- *How the linker lays it out* (`/MAP/FULL`, `ANALYZE/IMAGE`). Each
  section is its own image section: `POC_DATA` copy-on-reference,
  `POC_CODE` read-only and shareable, and `POC_CONST` and `POC_ADDR`
  each "READ WRITE NON-SHAREABLE ADDRESS DATA", plus the fix-up vectors.
  So the linker already keeps an `.ADDRESS` out of the code, but today
  it takes the whole of `POC_CONST`, strings and real constants
  included, out of sharing; with proposal 5 only `POC_ADDR` is.
- *The failure cases each print a message.* No logical name and no
  `SYS$SHARE:SHRLIB.EXE`: `%DCL-W-ACTIMAGE` with `-CLI-E-IMAGEFNF`. The
  image relinked and the program not: `-SYSTEM-F-SHRIDMISMAT, ident
  mismatch with shareable image` (proposal 3). The image without the
  key the program names: `%LINK-W-NUDFSYMS` and `%LINK-I-UDFSYM
  POC_K1_0123456789ABCDEF` - a warning, the image still written, so the
  build procedure's `ON WARNING THEN EXIT` is what stops it.
- *A hyphen in a directory name works*: `CREATE/DIRECTORY
  [.SHRTEST.VAX-DEC-VMS.OC]`, a file copied in and listed, so the VMS
  tuple directory can keep the triple's spelling (proposal 6).

### 18.5 Done

- *`POC_ADDR`* (proposal 5, 2026-10-12). The type descriptors, with
  their ProcTabs and base-type lists, are written in `POC_ADDR`,
  defined with its attributes where a module first uses it, and
  `PocRtl.mar`'s table of trap texts moves there too; the root tables
  were already in `POC_DATA`. No other constant poc writes holds an
  address. 23 fixtures' `expected-vax*.mar` change in one line each,
  the `.PSECT` before the descriptors.
- *`-library` for the VAX, and `POCRTL`* (proposals 1, 2 and 4,
  2026-10-12). `poc -target vax-dec-vms -library <name> <file>...`
  makes the library in `<output-dir>/vax-dec-vms/<O2|OC>/` as on LLVM
  (`Poc.BuildLibraryVax`): its modules' `.sym` and `.mar`, compiled from
  source only, any `.mar` file named copied beside them (a part, as
  `PocRtl.mar` is `POCRTL`'s; copied a line at a time, so that poc on
  VMS can too), the manifest and the `.owner` files, and two DCL
  procedures (`VaxToolchainDriver.WriteLibraryProcedures`).
  `<name>_build.com` assembles everything, makes `<NAME>.OLB` a module
  at a time with `LIBRARY/INSERT`, and links `<NAME>.EXE` shareable
  from the objects and each needed library's image, with every global
  symbol of its `.mar` files `UNIVERSAL=`: a label `::`, an assignment
  `==` and an `.ENTRY`, which MACRO makes global (MACRO 5.4, section
  3.3), read back from the files (`ReadGlobalSymbols`). Every library but
  `POCRTL` needs `POCRTL`, made by `poc -target vax-dec-vms -library
  POCRTL rtl/vax/*.Mod rtl/vax/PocRtl.mar`: its code calls `POC_TRAP` and
  the runtime's other routines, which a shareable image cannot leave
  undefined. Fixture `vax-library`: `POCRTL`, and `VAXLIB` of three
  dependent modules (a type-bound procedure, an exported variable, `NEW`),
  built on the guest, and a program linked against their shareable images
  (6 blocks) and against their object libraries (47 blocks), both
  printing what they should. Its `expected-VAXLIB_build.com`,
  `expected-VAXLIB_setup.com`, `expected-VAXLIB.library` and
  `guest-library.com` were reviewed by the user (2026-10-12).
- *Two changes to proposal 6, found on the guest.* The build procedure
  is `<name>_build.com`, not `<name>.com`: once the setup procedure has
  defined the logical name `<NAME>`, `@<NAME>` runs the image, since RMS
  takes a file specification without punctuation as a logical name
  (`%DCL-E-OPENIN ... POCRTL.EXE`). And `<name>_setup.com` defines only
  its own library's names, since it cannot know where a needed library
  is on VMS; instead a build procedure checks that `POC$LIB_<NEED>` is
  defined for each library it needs, and stops, before doing anything,
  with "library VAXLIB needs library POCRTL: run its POCRTL_SETUP.COM
  first" (`%X1000002C`, `SS$_ABORT` with its message inhibited).
- *`-build` against libraries* (2026-10-12). A program's module may
  come from a VAX library; `-build`'s procedure checks, as a library's
  does, that each library the program uses has been set up, and links
  each one's object library, `POC$LIB_<NAME>:<NAME>.OLB/LIBRARY`, in link
  order (a library before those it needs), or with `-shared-libraries`
  its shareable image, `POC$LIB_<NAME>:<NAME>.EXE/SHAREABLE`, found at
  run time by the logical name `<NAME>`. With `POCRTL` on the library
  path the program always links it, and the runtime's modules come from
  it, not from `rtl/vax`'s source, and `POCRTL.OBJ` is not linked; with
  no library, the procedure is what it was (`vax-build`'s are unchanged).
  `vax-library` builds its program both ways with `-build`
  (`expected-useolb.com`, `expected-useshr.com`) and runs both on the
  guest; those files and the new `guest-library.com` were reviewed by
  the user (2026-10-12).
- *`-install-library` for the VAX* (2026-10-12).
  `poc -target vax-dec-vms -install-library <name>` copies what the host
  has of the library (`Poc.InstallLibraryVax`) into
  `<base>/vax-dec-vms/<O2|OC>/`, as on LLVM: each module's `.sym`,
  `.owner` and `.mar`, its parts' `.mar`, its two DCL procedures and,
  last, the manifest, each as text with `Files`, not the shell, so that
  poc on VMS can too. The manifest now lists the parts, a `part <name>`
  line each (`Libraries.Library.parts`), which was not needed until a
  library was copied. `<NAME>.OLB` and `<NAME>.EXE` are made where it is
  installed, by running its `<name>_build.com` there, whose setup
  procedure then names that directory. The refusals are LLVM's: the
  library is in that directory already (found by a file made there and
  looked for in the library's own directory, which needs no shell), or a
  module of it is another library's there; a copy installed before has
  its modules' and parts' files removed first. `vax-library` installs
  `POCRTL` and `VAXLIB` twice into `inst`, checks every file is copied
  whole, builds its program against `inst` and checks both refusals;
  `vax-emit-errors` no longer has an `-install-library` case, and the
  refusal for a later phase (`ReportUnavailable`) is gone.
- *The library path on VMS* (proposal 6, 2026-10-12). `Directories`
  has two more procedures, in all three runtimes: `MakeSubdirectory`,
  the join proposal 6 asked for (on Unix `MakePath`'s; on VMS `[A]` and
  `B` give `[A.B]`, `[]` gives `[.B]`, a rooted `[A.]` gives `[A.B]`),
  and `NameStart`, where a file's own name starts in a path (after the
  last `/`; on VMS after the last `:`, `]` or `>`), which `-o` and a
  part's `.mar` now use. The guest showed that `LOG:[.B]` and `LOG:[B]`
  find nothing when `LOG` is not a rooted logical name, so on VMS
  `MakeSubdirectory` first translates a directory that does not end in
  `]` or `>` (`Platform.GetEnv`, a search list's first string, at most
  ten times). `Libraries` makes every tuple directory with it
  (`TargetDirectory`), so on VMS a library is in
  `[<base>.VAX-DEC-VMS.<O2|OC>]`. poc on VMS (`BuildInfo.defaultTarget`
  set) reads the logical name `POC$LIBRARY`, a search list, where Unix
  reads `POC_LIBRARY_PATH` (`-help` and poc(1) say so), and finds its
  own library directory without a shell: `[<parent>.LIB.POC]`, where
  `<parent>` is the directory above the one its image is in
  (`Libraries.VmsLibraryDir`). `vax-platform`'s `PlatformOut` checks
  both new procedures on Unix and on the guest, and its reviewed
  `expected-vax-Directories.mar` has the new code, reviewed by the user
  (2026-10-12).
  A one-off run on the guest, with V1's `POC.EXE` linked in `[.LP.POC]`
  (not a fixture: linking poc there takes the guest for a long while),
  had poc on VMS print the path with and without `POC$LIBRARY` (one of
  its strings a logical name), build `POCRTL` into `[-.L1]` and `VAXLIB`
  into the logical name `LPL2`, install both into its own
  `[.LP.LIB.POC]`, find them there with `POC$LIBRARY` gone, and build
  `VAXLIB`'s program against them; their build procedures, run in the
  installed directory, made the libraries, and the program printed
  "total 25" and "count 12".
- *`POC$IMPORT`* (2026-10-12, the user: the two names should be
  consistent). On VMS the import path's logical name is `POC$IMPORT`,
  named as `POC$LIBRARY` is, in place of `POC_IMPORT_PATH`, which Unix
  keeps; `tools/vax-guest-poc` defines it, and `-help` and poc(1) name
  both.
- *DCL's limits, response files and wildcards* (2026-10-12; the user
  chose both). Measured on the guest: DCL reads a command procedure's
  record of 256 bytes but refuses one of 258 (`%RMS-W-RTB`, which stops
  the procedure, `SET NOON` or not); continuation lines take a command
  past that, but a foreign command's arguments are one command element,
  of at most 255 characters (`%DCL-W-TKNOVF`), continued or substituted
  from a symbol alike, and past about 940 characters the 1024-byte
  command buffer overflows first (`%DCL-W-BUFOVF`). The procedures poc
  writes stay far inside the first limit (their longest lines are under
  160 characters, bounded by names), but a poc command line with a
  library's modules does not fit the second. So poc reads its arguments
  through `Poc.ReadArguments`: an argument `@file` stands for the
  arguments in the file, one a line (blanks at either end and a CR
  dropped, empty lines skipped), nested to a depth of 8, on Unix too,
  and `@@text` stands for `@text` (the user's suggestion, so that
  `-link @@x` still gives clang its response file `@x`);
  and on VMS an argument that is not an option and has `*` or `%` is
  replaced by the files it matches, as a Unix shell would, in RMS's
  order, versions dropped, an error when none does. `Directories` has
  `Search`, `StartSearch` and `NextFile` for that, in all three
  runtimes (on Unix the pattern itself, once), over `POC_FIND_FILE` and
  `POC_FIND_FILE_END` in `PocRtl.mar` (`LIB$FIND_FILE`,
  `LIB$FIND_FILE_END`; LIB$ manual 5.0, LIB-155 to LIB-159).
  `poc-response-files` tests the response files on Unix;
  `vax-platform`'s `PlatformOut` tests `NextFile` on both. A one-off
  guest run with V1's poc (linked there in under two minutes) had
  `POC$IMPORT` give the import path, a pattern matching nothing and a
  missing response file each refused (status 1), `-library POCRTL
  [-.RTL]*.MOD [-.RTL]*.MAR` build the runtime's library, `POC @ARGS.TXT`
  (naming `@MODS.TXT`, one of whose lines is a pattern) build `VAXLIB`,
  and `-build VAXLIBUS%.MOD` link a program against both, which printed
  "total 25" and "count 12".
- *Collisions across libraries* (proposal 7, 2026-10-12). Before
  `WriteMacro32` writes anything, `VaxCodeGenerator.EnterInterface`
  enters in the program's table the global symbols of every module of
  the closure it does not write, one from a library or given as its
  `.sym`, recomputed from what the `.sym` declares by the generator's own
  rules: each exported variable and procedure, each type-bound
  procedure (a `.sym` lists every one, hidden ones included, as forward
  declarations) and the descriptor of each record type it declares. A
  clash between two such modules stops the build there ("`A.X` and `B.Y`
  have the same VAX symbol, ..., in one program (rename one)"); a
  written module's clash with one is an error at its own declaration, as
  before. The check that two modules' names differ in more than case now
  covers them too. A record type or type-bound procedure that a `.sym`
  leaves out, which no importer can reach, is still caught at the link
  (layer 1: `MULDEF`, fatal in every build procedure). `vax-library`
  builds vax-build's colliding pair with one or both in a library: a
  program's `-build`, and a library's, are refused.
- *The failure cases* (proposal 8, 2026-10-12), as 18.4 found them by
  hand, now with poc's libraries, in `vax-library`'s
  `guest-library.com`: `USESHR` run with the logical name `VAXLIB`
  gone, `%DCL-W-ACTIMAGE` and `-CLI-E-IMAGEFNF`; run again after
  `VAXLIB_BUILD.COM` has relinked the image, `-SYSTEM-F-SHRIDMISMAT`
  (no `GSMATCH`, proposal 3); and `STALE.COM`, a program compiled
  against a `VAXLIB` whose `VaxLibSums` exports one more constant (made
  on the host, its module renamed `STALEUSE` to sit beside the other),
  linked with the real one: `%LINK-W-NUDFSYMS` and `%LINK-I-UDFSYM` for
  the other key, and the procedure stops there. Each is VMS's own
  message and a failing status, not a crash.
- *Step 1 is complete.*
- *The shareable image from the object library* (2026-10-15, approved
  by the user). LINK holds every input file open, and a process's
  quotas stop that near a hundred: on the development system `POC` has
  FILLM 100 and BYTLM 8000, and CHANNELCNT is 127, so `VMSDEF`, 243
  modules generated from SDL (Phase 17 step 5), failed with
  `%LINK-F-OPENIN` and `-SYSTEM-F-EXBYTLM`. `<name>_build.com`'s options
  file now takes the modules from the `.OLB` it has just made,
  `<NAME>.OLB/INCLUDE=(...)`, one module to a continued line: one file
  open, the same image. A hand-written part, whose module name (its
  `.TITLE`) need not be its file's, is still linked as its `.OBJ`.
  A program's `-build` still names each module's `.OBJ`: poc's own has
  35.

## 19. poc's runtime on VMS (Phase 17 step 3)

Step 2 decided that every interface in `rtl/llvm` comes to VMS, in
`POCRTL`, in import order (`doc/research/vms-module-inventory.md`,
proposals 1 to 6). This section records how each one is done, starting
with `Platform`. The sources are the 5.0 RMS manual (`AA-LA83A`), the
5.0 LIB$ manual (`AA-LA76A`) and the 5.5 System Services Reference
(`AA-LA69B`).

### 19.1 Platform: proposals

`rtl/vax/Platform.Mod` has 4 of the 46 procedures (`GetEnv`, `System`,
`Unlink`, `Exit`), plus `PID`, `CWD` and `NL`. The other 42 come over
new routines in `PocRtl.mar`, as the existing ones do. **Approved by the
user, 2026-10-12**, all eight as written.

1. **A `FileHandle` is a small number, an index into `Platform`'s own
   table of open files.** Each entry has its RMS blocks (a FAB, a RAB, a
   NAM block, an XABFHC and an XABRDT), a 512-byte block buffer, the
   file's length and the position. `StdIn`, `StdOut` and `StdErr` (0, 1
   and 2) are `SYS$INPUT`, `SYS$OUTPUT` and `SYS$ERROR`:
   - `Read` from `StdIn` reads records, with an LF after each.
   - `Write` to `StdOut` or `StdErr` goes through `LineOutput`: each LF
     ends a record, so the output comes out in order with `Out`'s and
     `Err`'s.

   The table holds 32 files, the 3 standard ones included. Opening one
   more gives an error that `TooManyFiles` recognizes, as does
   `SS$_EXQUOTA`.
2. **Files by handle are `Files`' files** (section 15, proposal 2):
   - `New` makes a new version of the name. That is VMS's answer to
     Unix's emptying of an existing file. The new version is Stream_LF
     with carriage-return carriage control, read and written by block
     I/O.
   - `OldRO` and `OldRW` open a Stream_LF, fixed-length or undefined
     file as its bytes.
   - `OldRO` reads a file of another record format a record at a time,
     with an LF after each, as `Files.Old` does. `OldRW` refuses such a
     file with `RMS$_ORG`, because writing bytes into it would break
     its records.
   - `Read`, `Write` and `Seek` work on the handle's position, through
     the block buffer, which is written back when the position leaves
     the block, at `Sync` (with `$FLUSH`), and at `Close`. Writing past
     the end fills the gap with zeros.
   - `Truncate` to a shorter length rewrites the block that holds the
     new end, with truncate-on-put (`RAB$V_TPT`, which needs `FAB$V_TRN`
     at open). RMS then puts the end of the file after the last byte
     written (RMS 7.19). Truncating to a longer length writes zeros.
   - `Size` is the handle's length.
3. **An `ErrorCode` is the VMS status of the service that failed**, as it
   is today: the whole longword under `-OC`, its low word under `-O2`.
   The low word keeps the message number and severity but not the
   facility. `Error()` is the last status that any of `Platform`'s
   procedures failed with, as errno is on Unix. The tests compare the
   message part:
   - `Absent`: `RMS$_FNF`, `RMS$_DNF`, `RMS$_DEV`, `RMS$_SYN`
   - `NoSuchDirectory`: `RMS$_DNF`, `RMS$_DIR`
   - `Inaccessible`: `RMS$_PRV`, `SS$_NOPRIV`
   - `TooManyFiles`: proposal 1's error, `SS$_EXQUOTA`
   - `DifferentFilesystems`: `RMS$_DEV` from a rename
   - `TimedOut`: `SS$_TIMEOUT`
   - `ConnectionFailed` and `Interrupted`: always FALSE. Nothing here
     makes connections, and VMS restarts no service when a signal
     arrives.
4. **Time is local time, because VMS 5.5 has no other.** The system
   clock is local, and nothing in 5.5 says what zone it is in:
   `SYS$TIMEZONE_DIFFERENTIAL` came later.
   - `GetClock` is `$GETTIM` taken apart by `$NUMTIM`.
   - `GetTimeOfDay` counts seconds and microseconds since 1 January 1970
     *local*, so it differs from Unix's count by the zone's offset.
   - `Time` counts milliseconds since the program started.
   - `Delay` is `$SETIMR` with a delta time and `$WAITFR` on an event
     flag that `LIB$GET_EF` allocates.
5. **A `FileIdentity` holds VMS's own identity of a file**, since its
   fields are not exported:
   - the device name (`NAM$T_DVI`) and the file ID (`NAM$W_FID`, three
     words), for `SameFile`;
   - the revision date (`XAB$Q_RDT`, a quadword of 100-nanosecond
     units), for `SameFileTime` and `MTimeAsClock`, the latter through
     `$NUMTIM`.

   `SetFileMTime` opens the file for writing, sets `XAB$Q_RDT` and closes
   it. RMS applies a revision date given at `$CLOSE` only to a file
   accessed for modification (RMS 15.1). The guest will show whether
   opening with `FAB$V_PUT` is enough or a write is needed.
6. **`System` runs its command in a subprocess through `LIB$SPAWN`**, and
   waits:
   - it returns 0 when the subprocess's completion status is a success;
   - otherwise it returns that status, narrowed to an `INTEGER` but never
     to 0;
   - it returns -1 if `LIB$SPAWN` itself fails.

   This is the VMS answer to `/bin/sh -c`. poc's own driver runs no
   programs on VMS (section 13), so it does not change.
7. **`Chdir` sets the default directory with `$SETDDIR`, and the default
   device by redefining `SYS$DISK`**, then updates `CWD`. On VMS both
   outlive the image, unlike a Unix process's working directory, which
   dies with it. So `Platform` records the originals on its first
   `Chdir` and puts them back from an exit handler, leaving DCL where it
   was.
8. **The rest**:
   - `Rename` is `$RENAME`. The new name becomes a new version, so an
     existing file of that name stays as an older one.
   - `MaxNameLength` is 39 and `MaxPathLength` 255 (ODS-2,
     `NAM$C_MAXRSS`).
   - `OSAllocate` and `OSFree` are `LIB$GET_VM` and `LIB$FREE_VM`, the
     size kept in a longword before the block.
   - `IsConsole` asks `$GETDVI` whether the handle's device is a
     terminal (`DC$_TERM`).
   - `getEnv` is `GetEnv`, but FALSE when there is no such logical name.
   - `LittleEndian` is TRUE, and `SeekSet`, `SeekCur` and `SeekEnd` are
     0, 1 and 2.
   - `SetInterruptHandler`, `SetQuitHandler` and
     `SetBadInstructionHandler` keep the handler and do nothing more
     until step 6, which decides how Ctrl-C (an AST) and a bad
     instruction (a condition) reach it.

**Testing.** `llvm-platform`, `llvm-platform-extra` and
`llvm-platform-files` run on the guest wherever their output does not
depend on the system. Where it does (error numbers, time zones,
`System`'s command), a VAX fixture of their own covers it.

### 19.2 Platform: done

- *Done* (section 19.1, proposals 1 to 8, 2026-10-12).
  `rtl/vax/Platform.Mod` has the whole interface, over 18 new routines
  in `PocRtl.mar`: `POC_FILE_OPEN_MODE`, `POC_FILE_TRUNCATE`,
  `POC_FILE_FLUSH`, `POC_FILE_IDENTITY`, `POC_SET_REVISION`,
  `POC_GET_TIME`, `POC_NUMTIM`, `POC_VECTIM`, `POC_DELAY`, `POC_SPAWN`,
  `POC_PARSE_DIRECTORY`, `POC_DEFINE_DISK`, `POC_SET_DIRECTORY` and its
  exit handler `POC_DIRECTORY_EXIT` (which puts the default directory
  back), `POC_IS_TERMINAL`, `POC_RENAME`, `POC_STATUS` and
  `POC_STATUS_CLASS`. Three things differ from the proposals:
  - Each file's control has an XABDAT, not an XABRDT: it reads the
    revision date on open. `SetMTime` sets it through a FAB of its own,
    opened for `PUT` with an XABRDT and closed with no write, which the
    guest showed is the way: a file closed after a write gets the
    current time instead.
  - `Truncate` writes the block holding the new end with `RAB$V_TPT`
    (truncate-on-put), which the guest showed truncates at VBN 1 too,
    to 0 bytes included.
  - A name with no 0X in its array names nothing, as in `rtl/llvm`:
    `GetEnv` finds no value, `System` returns -1, and a file procedure
    returns `RMS$_FNF`, which `Absent` recognizes. A name too long for
    a service gets `SS$_BADPARAM`.

  `StdOut` and `StdErr` write through `LineOutput`, so `Platform`
  imports it. `FileIdentity` is 32 bytes: the device name (counted, at
  most 16), the file ID and the revision date. Fixture
  `vax-platform-files`, new, is `llvm-platform-files` for VMS, with
  the checks of `llvm-platform` and `llvm-platform-extra` that do not
  depend on the system: 70 checks, passing on the guest under `-O2`
  and `-OC`. Its `guest-run.com` checks that the default directory and
  `SYS$DISK` are put back after the program changes them. The rest of
  those two fixtures runs Unix commands and is not repeated. In
  `vax-platform`, `System("exit 1")` is 256 under LLVM and 0 on VMS
  (an odd status is success), and `expected-vax-Platform.mar` is new.
  `vax-library`'s `POCRTL` makes 198 symbols universal, 66 more.

### 19.3 Files: proposals

`rtl/vax/Files.Mod` has the part of the interface poc's own source uses
(section 15, proposal 2): `New`, `Old`, `Register`, `Close`, `Length`,
`Set`, `Base`, `Read`, `Write`, `ReadString`, `ReadLine`, `WriteString`
and `Delete`. The rest comes over `Platform` (section 19.1) and a few
more routines in `PocRtl.mar`. Section 15's model stays: a file `Files`
makes is Stream_LF, read and written by block I/O a 512-byte block at a
time, and a file of another record format is read a record at a time,
with an LF after each. The sources are the 5.0 RMS manual (`AA-LA83A`)
and the 5.5 System Services Reference (`AA-LA69B`). **Approved by the
user, 2026-10-12**, all nine as written.

1. **The whole interface, as `rtl/llvm`'s.** `Purge`, `GetDate`,
   `GetName`, `Pos`, `ReadByte`, `ReadBytes`, `WriteBytes`, `Rename`,
   `ChangeDirectory`, `SetSearchPath`, the typed riders (`Read`/`Write`
   `Bool`, `Int`, `LInt`, `Set`, `Real`, `LReal`, `Num`), and
   `MaxPathLength` and `MaxNameLength` (255 and 39, `Platform`'s). Each
   has `rtl/llvm`'s comment and behaves as it does there, except where
   these proposals say otherwise.

2. **`Old` opens a file to be read, and the first write reopens it to
   be written.** RMS sets a file's revision date to the time of its
   `$CLOSE` whenever it was opened for writing, written to or not (RMS
   Reference, chapter 15; and on the guest, 2026-10-12). If `Old`
   opened every file to be read and written, as `rtl/llvm`'s does when
   the system allows, every file poc reads would get a new date. Instead
   `Old` opens it for `GET` with block I/O. The first `Write`,
   `WriteBytes`, typed write or `Purge` closes it and opens it again
   for `GET` and `PUT`. If it cannot be opened for writing (no
   privilege), or its format is not Stream_LF, fixed-length or
   undefined, the program stops with "error writing file" and
   `HALT(99)`, as `rtl/llvm`'s does when a write fails. Both opens share
   with `SHRGET`, `SHRPUT` and `UPI`, the only sharing RMS allows for
   block I/O (RMS Reference, `FAB$B_SHR`). So two `Old` calls for one
   file give two independent Files, as on Unix (vishap-bugs D14).

3. **A File stays usable after `Close` and `Register`, as on Unix.** The
   next operation opens it again: to be read, or to be written as in
   proposal 2. Today a File can be written only before its `Close`, and
   a File `Old` opened can never be written.

4. **`GetDate` is the revision date.** It writes out the block, reads
   the date with `$DISPLAY` into the control's XABDAT, and converts it
   to `t` and `d` as `Platform.MTimeAsClock` does. A File written since it was last
   opened is given the current time: RMS sets its date only when it is
   closed, and then to the time of the `$CLOSE`. A New file not yet
   written to is made first, as `rtl/llvm`'s is.

5. **New names are fixed when they are given.** `New` has `$PARSE`
   expand the name against the current default directory and keeps the
   result without its version (a new routine, `POC_EXPAND_NAME`). The
   temporary file is made, and `Register` names it, there, even if the
   program has called `ChangeDirectory` in between, as on Unix.
   `GetName` gives the name `Old` was asked for, or `New`'s name once
   the file is registered. Before that it gives the temporary file's
   full resultant name (`DUA1:[USERS.POC]POC_000002A4_1.TMP;1`), or "" if
   it has not been made yet.

6. **The search path is VMS directories.** The directories are
   separated by "," (";" as in voc until 2026-10-13, when the user chose
   "," to match `POC$IMPORT` and `Directories`), and blanks around them
   are ignored. Each is a
   directory specification (`[.SUB]`, `DUA1:[X.Y]`) or a logical name;
   a bare logical name gets a ":" after it. A leading "~" stands for
   `SYS$LOGIN`. `Old` puts each directory in front of the name, in
   turn. A name with ":", "[" or "<" in it is looked for only where it
   says, as a name with "/" is on Unix. A search-list logical name
   (`DEFINE LIB [A],[B]`, `Old("LIB:X.TXT")`) works too, because RMS
   handles it itself.

7. **`Delete`, `Rename` and `ChangeDirectory` are `Platform`'s**
   (section 19.1): `Unlink` deletes the highest version, `Rename` makes
   the new name a new version, and `Chdir` sets the default directory.
   As with `Register`, an existing file of the new name stays, as an
   older version, where on Unix it is replaced. `Old` of the name finds
   the new one either way.

8. **The typed riders write Oakwood's format, the same bytes as on
   Unix.** That is the step 2 decision (`vms-module-inventory.md`,
   proposal 4). Integers, sets, Booleans, strings and `WriteNum`'s
   numbers need no change. A `REAL` is converted between F_floating and
   IEEE single, a `LONGREAL` between G_floating and IEEE double, by
   `Files`' own code. Each pair has the same field widths. The exponent
   is 2 more on the VAX: a VAX fraction is 0.1f where IEEE's is 1.f, and
   the bias is 128 or 1024 where IEEE's is 127 or 1023. And a VAX value's
   16-bit words are in the other order. Where the ranges differ:
   - Writing: a VAX value whose exponent field is 1 or 2 becomes an IEEE
     denormal, rounded to nearest, ties to even. VAX zero is IEEE +0.
   - Reading: an IEEE denormal or zero becomes VAX 0, since the VAX has
     neither denormals nor -0.
   - Reading: an IEEE value too large for the VAX (exponent field 254 or
     2046), or an infinity, becomes the largest VAX value of its sign.
   - Reading: a NaN becomes the VAX reserved operand (sign 1, exponent
     0). Arithmetic on it stops the program with a reserved-operand
     fault, the nearest thing the VAX has to a NaN.

9. **Files are finalized, as on Unix.** Each File is registered with
   `GarbageCollectedHeap.RegisterFinalizer`. When it is no longer
   reachable, or the program ends (the collector's exit handler, which
   runs after a trap too), its block is written out and it is closed.
   A New file never registered has its temporary file deleted.

**Testing.** `llvm-files-riders`' `riders.mod` and `signed.mod` run on the
guest under `-O2` and `-OC`. They must print what they print under
LLVM, the dump of the typed riders' bytes included. Only `riders.mod`'s
three directory names are changed, with sed, to VMS ones (`riders.sub`
to `[.RIDERSSUB]`, `..` to `[-]`). `llvm-files` and `llvm-files-extra`
check their files with Unix commands, so a new fixture,
`vax-files-extra`, makes the same checks with DCL's. `vax-files` keeps
its checks of reading variable-length and VFC files.

### 19.4 Files: done

- *Done* (section 19.3, proposals 1 to 9, 2026-10-12).
  `rtl/vax/Files.Mod` has the whole interface. It imports `Platform`
  and `GarbageCollectedHeap`, and uses three routines that are new or
  changed in `PocRtl.mar`:
  - `POC_FILE_REOPEN` takes a third argument: 1 opens the file to be
    written, refusing a format other than Stream_LF, fixed-length or
    undefined.
  - `POC_EXPAND_NAME` is New's `$PARSE`.
  - `POC_FILE_NAME` gives the resultant name.

  Every open shares with `SHRGET`, `SHRPUT` and `UPI`. That includes
  `POC_FILE_CREATE`'s, beyond proposal 2, so that `Old` of a New file's
  temporary name works while the New file is open, as on Unix.
  `Platform.OldRO`'s open shares the same way. On the guest RMS accepts
  this sharing on variable-length and VFC files read a record at a time
  too (`vax-files`).
- *Fixtures.*
  - `vax-files-riders`, new, runs `llvm-files-riders`' two programs on
    the guest. It takes its expected output from that fixture's
    `expected`, with `exit=2` as `status: %X10000012`. The trap's
    message is on `SYS$ERROR`, typed before the status where Unix's
    `2>&1` shows it. The dump of the typed riders' bytes is the same as
    on Unix, and so are `KEPT.TXT`, written out by the collector's exit
    handler after a trap, and no `POC_*.TMP` left.
  - `vax-files-extra`, new: 75 checks. 1-36 are `llvm-files`', 37-54
    `llvm-files-extra`'s, with DCL for the shell. 55-75 check section
    19.3: the date kept by a read, two Files on one file, `Purge`, the
    search path with "~" and a logical name, and eleven real
    conversions at the edges, including denormal ties both ways.
  - `vax-files` compares the three modules `Files` now imports, each the
    same as a reviewed copy elsewhere.
  - `vax-library`'s `POCRTL` makes 226 symbols universal, 28 more.
- *Changed* (the user, 2026-10-13): the search path's directories are
  separated by ",", not ";", so that it reads as `POC$IMPORT` and
  `Directories` do (proposal 6). `vax-files-extra`'s checks 62-64 use
  ",".

### 19.5 Modules: proposals

`rtl/vax/Modules.Mod` has the command line (section 15, proposal 6;
section 16, proposal 6): `ArgCount`, `GetArg`, `GetIntArg` and `ArgPos`,
the line from `LIB$GET_FOREIGN` split at blanks outside quotes and
argument 0 the image's name. `rtl/llvm`'s also has the list of modules
and their commands (`ThisMod`, `ThisCommand`, `Free`, `res`, `resMsg`,
`imported`, `importing`, the `Module` and `Cmd` records), voc's run-time
error stops (`Halt`, `AssertFail`), `ArgVector`, `MainStackFrame`,
`BinaryDir` and `Init`. The list rests on a descriptor of each module,
which the LLVM backend writes and each module's initializer registers
(`ModuleTable.Mod`, "MODULE DESCRIPTORS"; Phase 12 step 5e). The VAX
backend writes none yet. **Approved by the user, 2026-10-13**, all eight
as written.

1. **The whole interface but `Init`.** `Init` is called by the `main` the
   LLVM backend writes, with C's `argc` and `argv`, and a program must
   not call it. On VMS the command line comes from VMS (section 15,
   proposal 6), so there is nothing for `Init` to do, and leaving it out
   means a program that calls it is told so when it is compiled.
2. **The VAX backend writes a module descriptor**, in `rtl/llvm`'s
   layout with every field a longword: the next descriptor (0, written
   when it is registered), the address of the module's name, the
   number of imports *I*, the number of commands *C*, the addresses of
   the *I* imported modules' names, then *C* pairs of a command's name
   and its procedure's address. A command is what it is on LLVM: an
   exported procedure, not type-bound, with no parameters and no
   result. The descriptor is `L_MODULE_DESCRIPTOR` in `POC_DATA`, since
   its first longword is written; the names are `.ASCIZ` in
   `POC_CONST`, under local labels; a command's address is its
   procedure's symbol. `SYSTEM` is not an import here, as on LLVM.
3. **Only in a program that contains `Modules`**, as on LLVM. The driver
   tells the backend so, as it tells it whether the program uses the
   collector (`withCollector`). A module compiled on its own
   (`-compile`, a library) has a descriptor only if `Modules` was among
   the modules compiled with it. `POCRTL` is built with `Modules`, so
   every module in it has one. Unlike LLVM's, VMS's linker keeps every
   object module it takes whole, so a command costs nothing more for
   being in its descriptor.
4. **The initializer registers the descriptor right after its imports'
   initializers**, before the module's body, as on LLVM: a module is
   found once its initialization has started. The call is `PUSHAL
   L_MODULE_DESCRIPTOR` and `CALLS #1, POC_MODULE`. The root table is
   still registered first (section 15, proposal 9).
5. **The list is kept by `PocRtl.mar`, not by a `ModuleTable` module.**
   On VMS the root tables are already `PocRtl.mar`'s (`POC_ROOTS`,
   `POC_ROOT_TABLES`), and `rtl/vax` has no `ModuleTable`. Two more
   routines, `POC_MODULE(descriptor)` and `POC_MODULES()`, the newest
   descriptor or 0, do the same for descriptors. `Modules` declares
   them `["VMS"]` and follows each descriptor's first longword to the
   next. One difference a program can see: `ThisMod("ModuleTable")` is
   NIL on VMS, since there is no such module.
6. **`ThisMod`, `ThisCommand`, `Free` and the records are
   `rtl/llvm`'s**, with the same differences from voc's (names of up to
   255 characters, commands in declaration order, `Free` unloading
   nothing). A command is called as any procedure value is on the VAX:
   its address is the entry mask, which `CALLS #0` takes. `Modules` uses
   `NEW`, so a program that contains it gets the collector, as on LLVM.
7. **`Halt` and `AssertFail` say what voc's say**, through `LineOutput`
   to `SYS$ERROR`, as `POC_TRAP`'s messages go, and then end the program
   with `Platform.Exit`. The status is section 14, item 10's: `Halt(0)`
   is `SS$_NORMAL`, and `Halt(n)` is `%X10000000 + 8*(n MOD 256) + 2`, so
   `Halt(-1)` and a failed `AssertFail(0)` both end as 255 does.
   Registered finalizers run afterwards, from the collector's exit
   handler (section 19.4).
8. **`ArgVector`, `MainStackFrame` and `BinaryDir` in VMS's terms.**
   - `ArgVector` is the address of an array of `ArgCount` longwords,
     each the address of an argument, 0X-terminated, in `Modules`' own
     copy of the line. That is C's `argv`, so code that walks it, as
     `Args` does, works unchanged.
   - `MainStackFrame` is an address near the bottom of the stack: a
     local variable's address in a procedure that `Modules`' body
     calls, as `rtl/llvm`'s is `argv`'s address. Nothing in poc uses it.
   - `BinaryDir` is the device and directory of the image's file
     specification, argument 0 (`JPI$_IMAGNAME`), such as
     `DUA1:[USERS.POC.BIN]`, in VMS's form, which `Files` takes. VMS
     always gives the image's full name, so there is no `PATH` to
     search as voc's `FindBinaryDir` does.

Fixtures on the guest, under `-O2` and `-OC`:

- `vax-modules-commands`, new: `llvm-modules-commands`' programs
  (`commands`, `halt`, `haltcode`, `assertcode`, `assertzero`), whose
  output must be LLVM's except for `ModuleTable` (proposal 5), the
  exit statuses (proposal 7), and `BinaryDir` (proposal 8).
- `vax-modules`, extended: `VaxModLib` gets a command, so that its
  `expected-vax-VaxModLib.mar` shows a descriptor, for review.
- `vax-modules-extra`, new: `llvm-modules-extra`'s checks, with its
  long argument as long as a DCL command line allows rather than 3000
  characters, and `ArgVector` read as `argv`.
- `expected-vax-Modules.mar` is new, and `vax-library`'s `POCRTL` gains
  `POC_MODULE`, `POC_MODULES` and `Modules`' new symbols.

### 19.6 Modules: done

- *Done* (section 19.5, proposals 1 to 8, 2026-10-13).
  `rtl/vax/Modules.Mod` has the whole interface but `Init`. It imports
  `Platform` and `LineOutput`, and uses `NEW`, so a program that
  contains it gets the collector.
  - `VaxCodeGenerator.WriteModuleDescriptor` writes each module's
    descriptor when the program contains a module named `Modules`
    (`Poc.Mod` sets `withModules`): the descriptor in `POC_DATA`, its
    names as `.ASCIZ` in `POC_CONST`. The initializer registers it with
    `POC_MODULE` after its imports' initializers. A module with no body
    still gets an initializer then.
  - `PocRtl.mar` keeps the list: `POC_MODULE` links a descriptor in at
    the head, and `POC_MODULES` returns the head.
    `tools/vax-runtime-stub.mar` has both, for debugger runs.
  - `Modules` reads the list lazily: `ThisMod` and `Free` first enter the
    descriptors registered since their last look, oldest first.
- *Fixtures.*
  - `vax-modules-commands`, new: `llvm-modules-commands`' five programs
    on the guest. Its expected MACRO-32 covers `commands`, `Greeter`
    (whose descriptor lists its two commands), `Modules`, and `Out`,
    `Platform` and `LineOutput` with their descriptors. The output is
    LLVM's, but `ModuleTable` is not found, and the statuses are
    `%X1000001A` for `Halt(3)`, `%X100007F2` for `Halt(-2)`,
    `%X1000003A` for `AssertFail(7)` and `%X100007FA` for
    `AssertFail(0)`.
  - `vax-modules-extra`, new: `llvm-modules-extra`'s eight checks, its
    long argument 200 zeros, and `ArgVector.mod`. `ArgVector.mod` reads
    each argument through `ArgVector` as `argv`, checks that
    `BinaryDir` is argument 0 up to its "]", and checks that
    `MainStackFrame` is in P1 space.
  - `vax-command-line`: `Modules` now brings in `Platform`, `LineOutput`
    and `GarbageCollectedHeap`. So `CommandLine`, the main module,
    starts the collector. The fixture compares `Platform` and
    `LineOutput` too, and links and deletes their objects on the guest.
  - `vax-library`'s `POCRTL` makes 242 symbols universal, 16 more.
- *Not done as proposed*: `vax-modules` was not extended. Its program
  does not import `Modules`, so it gets no descriptors, and a command
  in `VaxModLib` would show nothing. `vax-modules-commands`'
  `expected-vax-Greeter.mar` shows a descriptor with commands instead.

### 19.7 RealDigits and Reals: proposals

The fourth group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `RealDigits` and `Reals` for F_floating and G_floating,
and with them `Out`'s and `Err`'s `Real`, `LongReal` and `Ten`.
Several `rtl/llvm` modules read a real's bits as IEEE 754's, which a VAX
value is not (section 14, item 9):
- `RealDigits.ExactDigits` reads the exponent and fraction.
- `FormattedText.RealP` tests for zero, the sign, infinities and NaNs.
- `Reals` reads `Expo`, `SetExpo` and `ConvertL` from the bits, and gets
  `Ten` and `TenL` from C's `strtof` and `strtod`.

`Files` already takes F and G apart (section 19.3, proposal 8). Every
decision here takes its layouts from that reviewed code:
- F: the sign is bit 15 and the exponent bits 14:7 (excess 128). The
  fraction is bits 6:0 and then the second word.
- G: the exponent is bits 14:4 (excess 1024), and the fraction runs on
  through three more words.
- Both: the value is 0.1f times 2 to the power (exponent - bias), and
  exponent 0 is zero, or the reserved operand when the sign is 1.

**Approved by the user, 2026-10-13**, all six as written.

1. **`rtl/vax/RealDigits.Mod` is `rtl/llvm`'s, with only the reading of
   the bits changed.**
   - `ExactDigits` takes a G_floating value apart: m = 2^52 + f, and e =
     exponent - 1077, so that v = m * 2^e exactly. The digits and
     rounding are then `rtl/llvm`'s, unchanged: nearest, ties to even,
     with no floating-point arithmetic.
   - A `REAL` reaches `Digits` and `Fixed` through `CVTFG`, which is
     exact.
   - A value with G's smallest exponent has up to 769 exact digits,
     which fits the 800-character buffer. Its big integer needs about
     2550 bits, under the 6000 there is room for.
   - The interface (`Digits`, `Fixed`) is unchanged, so `Out` and later
     `Texts` call it as on LLVM.
2. **`rtl/vax/FormattedText.Mod` is `rtl/llvm`'s, with `RealP`'s tests
   changed.**
   - Zero is `x = 0`, and the sign is `x < 0`.
   - The `Infinity` and `NaN` branch goes, since the VAX has neither.
     The reserved operand faults on the first comparison, as any use of
     it does (section 19.3, proposal 8).
   - Everything else is the same text, so `Out.Real(x, n)` prints what
     it prints on LLVM for every value both formats hold.
   - Changing `rtl/llvm`'s module instead, to test without the bits,
     would lose `-0`, `Infinity` and `NaN` on Unix. It would also change
     a module Stage 0 builds.
   - `Ten`, by repeated squaring, is exact up to 10^22 on both. It
     changes in one place: on LLVM it squares once more after the last
     bit of e it uses. For e >= 256 that last square is past G's range,
     which ends just under 9 * 10^307. On LLVM the infinity is thrown
     away, but on the VAX it is a floating-overflow fault. The VAX copy
     stops squaring once e is used up, so `Ten(256)` to `Ten(307)` work.
     Past 307 it stops on the VAX's floating overflow, where LLVM gives
     infinity.
3. **`Out` and `Err` get `Real`, `LongReal`, `Ten` and `IsConsole`**,
   with `rtl/llvm`'s interface and output, which completes both
   interfaces.
   - `Real` and `LongReal` get the text from `FormattedText`, then write
     the blanks that fill the field and the text, through `LineOutput`,
     as `Int` already does. `LineOutput` itself is unchanged, so its six
     reviewed copies stay as they are.
   - `IsConsole` is set by each module's body. A new `PocRtl.mar`
     routine, `POC_IS_TERMINAL`, asks `$GETDVIW` for the device class
     (`DVI$_DEVCLASS`) of `SYS$OUTPUT` or `SYS$ERROR`. The answer is
     TRUE when that class is `DC$_TERM` (System Services 5.5,
     `$GETDVI`), and FALSE when the call fails.
   - `IsConsole` comes now rather than in `VT100`'s step because
     `llvm-out`'s and `llvm-err`'s programs print it.
   - The part-line `Flush` to a terminal stays in `VT100`'s step.
4. **Decimal to F and G by poc's own conversion: a new internal module,
   `rtl/vax/DecimalToReal.Mod`** (the inventory's proposal 3).
   - It is `src/front/DecimalToDouble.Mod`'s exact method, with
     `HUGEINT` for its 8-byte `LONGINT`, which the runtime cannot assume
     under `-O2`. The method is a big-integer binary search for the
     significand, and a comparison with the midpoint, so ties go to
     even.
   - G's parameters are 53 bits, no value below 2^-1024 and a last bit
     of at most 2^970; F's are 24 bits, 2^-128 and 2^103.
   - `ToLongReal(numeral, VAR value): BOOLEAN` and `ToReal` give the
     nearest value, and FALSE beyond the largest. Below the smallest
     value the result is the nearer of 0 and the smallest, since the VAX
     has nothing between them.
   - `Reals` uses it now. `Strings`, `In`, `InStr` and `FormattedInput`
     use it in their steps.
   - Ties go to even, as IEEE rounds and as `RealDigits` does, not away
     from zero as the VAX's own arithmetic and MACRO do (section 14, item
     9). So a numeral exactly halfway between two values can differ in
     its last bit from the same numeral written as a constant in a
     program. Everywhere else the two agree.
5. **`Reals` on the VAX.**
   - `Ten(e)` and `TenL(e)` are `DecimalToReal`'s value of "1E<e>",
     built by `PowerText` as on LLVM. Beyond the range they give the
     largest value of the type. `Files` reads an IEEE infinity the same
     way (section 19.3, proposal 8), and a VAX value cannot overflow to
     anything else. Below the range they give 0, as LLVM does past its
     subnormals.
     - On LLVM, `Ten(39)` and `TenL(309)` are infinity. Here they are
       the largest F and G values.
     - `TenL(-309)` to `TenL(-323)` are subnormals on LLVM and 0 here.
     - `Ten(-38)` is a full-precision normal number here, where it is a
       subnormal on LLVM.
   - `Expo`, `SetExpo`, `ExpoL` and `SetExpoL` read and write the VAX's
     own exponent field: 8 bits excess 128, and 11 bits excess 1024. So
     `Expo(1.0)` is 129, where IEEE's is 127. The interface promises
     "the biased exponent field of x", and code that wants IEEE's on the
     VAX is already wrong about the fraction and the bias.
     - `Texts`' `RealBits` assumes IEEE's field and sign bit. It gets
       its VAX answer in `Texts`' own step.
     - `SetExpo(x, 0)` of a negative x makes the reserved operand, as
       writing that field by hand would.
   - `ConvertL` takes m and e from G's fields as in proposal 1, then
     writes digits as on LLVM. `Convert` is `ConvertL` of `LONG(x)`. A
     zero or the reserved operand writes zeros.
   - `ConvertH` and `ConvertHL` are unchanged: the bytes as they are in
     memory, least significant address first, as voc's document. On the
     VAX those are F's and G's bytes, so `ConvertH(1.0)` is "80400000",
     where IEEE's is "0000803F".
6. **Fixtures on the guest, under `-O2` and `-OC`.**
   - `vax-real-digits`, new. `llvm-real-digits/generate.py` also writes
     a VAX program and its expected output.
     - The program's values are `llvm-real-digits`' values that are
       normal in both formats: 2^-1022 to just under 2^1023 for a
       `LONGREAL`, and 2^-126 to just under 2^127 for a `REAL`. The same
       oracle, the C library's correctly rounded `%e`, holds for them.
     - Some values only the VAX has are added: its smallest and
       largest of each type, and a few between 2^-1024 and 2^-1022 and
       between 2^-128 and 2^-126, with digits from Python's exact
       fractions.
   - `vax-reals-module`, new: `llvm-reals-module`'s `reals.mod` and
     `beyond.mod`, built for the VAX.
     - Their expected output is the VAX's: F's and G's bytes, fields
       and ranges.
     - It is written by a generator from the formats' definitions and
       Python's exact fractions, not by running the programs.
   - `vax-out-reals`, new.
     - `llvm-out-extra`'s `outextra.mod` and `llvm-err`'s `errtest.mod`
       must print their LLVM `expected` on the guest. Neither uses an
       infinity, a NaN or a -0.
     - `llvm-out`'s `outtest.mod` runs too, without the lines that make
       an infinity and a NaN by multiplying past the range, which fault
       on the VAX.
     - The procedure sends `SYS$OUTPUT` and `SYS$ERROR` to files, as the
       LLVM fixtures redirect them, so `IsConsole` is FALSE for both.
       TRUE is checked by hand in a telnet session, since `tools/vax-do`
       sends everything to a log file.
     - The VAX rounds a tie away from zero, so where a program computes
       a tie, as `outtest`'s repeated multiplications by ten might, its
       last digit can differ from LLVM's. Any such line is reported in
       the fixture's own expected output, with the reason, not hidden.
   - `vax-library`'s `POCRTL` gains `RealDigits`, `FormattedText`,
     `DecimalToReal`, `Reals` and the new `Out` and `Err` procedures.
     `vax-out` and `vax-err` gain those procedures in their reviewed
     `expected-vax-Out.mar` and `expected-vax-Err.mar`.

### 19.8 RealDigits and Reals: done

- *Done* (section 19.7, proposals 1 to 6, 2026-10-13). Four new
  modules in `rtl/vax`, and `Out` and `Err` complete:
  - `RealDigits.Mod` is `rtl/llvm`'s, but `ExactDigits` takes a
    G_floating value apart.
  - `FormattedText.Mod` is `rtl/llvm`'s, but `RealP` tests the sign and
    zero with `TSTG`, there is no Infinity or NaN, and `Ten` stops
    squaring once e is used up.
  - `DecimalToReal.Mod` is `src/front/DecimalToDouble.Mod`'s method with
    `HUGEINT`, for G and F, saturating past the largest value.
  - `Reals.Mod` gets `Ten`/`TenL` from `DecimalToReal` and reads the
    VAX's own exponent fields.
  - `Out` and `Err` get `Real`, `LongReal`, `Ten` and `IsConsole`
    through `FormattedText`.
- *Not done as proposed*:
  - `IsConsole` calls `POC_IS_TERMINAL`, which `Platform.IsConsole`
    already had in `PocRtl.mar` (section 19.1), rather than a new
    routine.
  - `SetExpo` and `SetExpoL` read and write `x` as an integer (`SYSTEM.GET`
    and `PUT`), not as a real. A floating move of a negative `x` with
    exponent 0 would fault inside `SetExpo`, where proposal 5 says the
    reserved operand faults only when it is used. A positive one would
    become a true zero, since the VAX takes any positive value with
    exponent 0 as an exact zero wherever it is used as a real (MACRO
    and Instruction Set 5.4, "Floating-point 0"). So `SetExpo(3.0, 0)`
    leaves the fraction bits in `x`, but `x` passed to `ConvertH` as a
    `REAL` is copied by `MOVF` and is 0 there.
- *What differs from LLVM on the guest*, all as section 19.7 predicted:
  - A numeral exactly halfway between two values is the upper one, as
    MACRO rounds ties away from zero: 1.0D23 and 8.41D21, which LLVM
    reads as the lower ones (`vax-real-digits`).
  - A computed tie is rounded the same way. `outextra`'s and `outtest`'s
    products of tens past 10^22 differ from LLVM's in their last digits
    (`vax-out-reals`). A Python model of both roundings gives every
    differing line exactly: 10^23, 10^40 and 10^300 as products, and a
    third of 10^300.
  - `Ten`, `TenL`, `Expo`, `ConvertH` and the rest give F's and G's
    answers (`vax-reals-module`).
  - `Err` writes to `SYS$ERROR`, which under `tools/vax-do` is the telnet
    session, not the log. `vax-out-reals` therefore sends `errtest`'s
    two streams to files and types them.
- *Fixtures.*
  - `vax-real-digits`, new: 1083 lines. `llvm-real-digits/generate.py`
    writes its `digits.mod` and `guest-run.expected` after its own
    files, which it leaves unchanged. The oracle is exact fractions and
    MACRO's rounding of each numeral.
  - `vax-reals-module`, new: `llvm-reals-module`'s `reals.mod`, as
    `RealsUse.mod` since VMS does not tell `reals` from `Reals`, and
    `beyond.mod`, 440 lines. Its `generate.py` writes the expected output
    from the formats' definitions; `generate.py ieee` reproduces what the
    two programs print on Unix, line for line.
  - `vax-out-reals`, new: `outextra`, `errtest` and `outtest`, with one
    expected file per size model, since `outtest` prints `MAX(INTEGER)`.
  - `Out` and `Err` now import `FormattedText`, which imports
    `RealDigits`. So the 22 fixtures whose programs use `Out` or `Err`
    on the guest send those two `.mar` files too and delete their
    objects.
    - `vax-out`, `vax-err` and `vax-modules-commands` compare them, and
      their `Out` or `Err`, with new expected copies.
    - Their main modules differ only in `Out`'s or `Err`'s key.
  - `vax-library`'s `POCRTL` has 13 modules and makes 280 symbols
    universal, 38 more.

### 19.9 FormattedOutput and OutStr: proposals

The fifth group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `FormattedOutput` and `OutStr`. On LLVM they are:
- `FormattedOutput` (Phase 11 A26) is internal. It is the formatting
  behind `Out` and `Err`, written once, with the file descriptor to
  write to as each procedure's first parameter. It writes through
  `FileDescriptorOutput`, which VMS does not have.
- `OutStr` (Phase 15's "Ongoing library enhancements" 1) is `Out`'s
  output procedures appending to a string. It is plain Oberon over
  `FormattedText`, and the inventory found it compiles for the VAX as it
  is. Its `String` takes a read-only parameter, `str-`, which the VAX
  backend passes as section 7 says.

On the VAX, `Out` and `Err` came before `FormattedOutput` and each
formats for itself (section 19.7, proposal 3). Each has its own `Field`,
`Real` and `LongReal` over `LineOutput` and `FormattedText`.

**Approved by the user, 2026-10-13**, all five as written.

1. **`rtl/vax/FormattedOutput.Mod`: `rtl/llvm`'s procedures over
   `LineOutput`, with `LineOutput`'s stream as the first parameter.**
   - `Char`, `String`, `Ln`, `Int`, `Hex`, `Ten`, `Real` and `LongReal`,
     with `rtl/llvm`'s comments and output.
   - The first parameter is `stream: INTEGER`, `LineOutput.output` or
     `LineOutput.error`, not a file descriptor. VMS has no descriptors,
     and the module is internal: only `Out` and `Err` call it, and they
     already name `LineOutput`'s streams.
   - `Char`, `String`, `Ln`, `Int` and `Hex` are `LineOutput`'s. `Real`
     and `LongReal` are the `Field` that `Out` and `Err` each have now,
     moved here. `LineOutput` itself is unchanged, so its reviewed copies
     stay as they are.
   - Output is kept until `Ln`, as now, not written at once as on LLVM.
     A record is written whole (section 15, proposal 8).
2. **`Out` and `Err` call `FormattedOutput`, as on LLVM.** Their own
   `Field`, `Real` and `LongReal` go, so the formatting of a number is
   in one place on both targets, as A26 intended. Their interfaces and
   output do not change, and `IsConsole` stays in each.
   - The cost is a ripple like section 19.8's. The 25 fixtures that send
     `Out`'s or `Err`'s `.mar` also send `FormattedOutput.mar`, and their
     guest procedures delete its object. `vax-out`, `vax-err` and
     `vax-modules-commands` get a new reviewed copy,
     `expected-vax-FormattedOutput.mar`, and their copies of `Out` or
     `Err` change again.
   - The alternative is to leave `Out` and `Err` as they are. Then
     `FormattedOutput` is a module that nothing in `POCRTL` imports, and
     the formatting stays in three places.
3. **`rtl/vax/OutStr.Mod` is `rtl/llvm`'s, unchanged.**
   - It is a copy, since a program finds `POCRTL`'s modules in
     `rtl/vax` alone (`rtl/vax/README.md`). Its header comment gains one
     line saying so.
   - `vax-outstr`'s `test.sh` compares the two files (`cmp`, ignoring
     that line), so a change to one that misses the other fails the
     gate.
4. **Fixture `vax-outstr`, new, on the guest under `-O2` and `-OC`.**
   - Its program is `llvm-outstr`'s `outstr.mod`, renamed if VMS's single
     case clashes with `OutStr`, as `RealsUse.mod` was (section 19.8).
     Every case is written by `Out`, then by `OutStr` into a string that
     `Out` writes, and the two lines must be the same. `test.sh` checks
     this as `llvm-outstr`'s does.
   - The lines that build a value from IEEE 754's bits go, since on the
     VAX those bits mean something else: the smallest subnormals, the
     infinities and the NaNs. Most of those bit patterns have exponent 0
     in F's or G's first word, so they would print as 0.
   - In their place are the VAX's own extremes: `MAX` and `MIN` of
     `REAL` and `LONGREAL`, which the VAX target writes as F's and G's
     largest values (section 14).
   - Its `expected` is `llvm-outstr`'s, without the removed lines and
     with the new ones. Their digits are computed from F's and G's
     largest values with Python's exact fractions, as
     `vax-real-digits`' are, and are not taken from the guest.
   - `Out`'s lines and `OutStr`'s are the same text from the same
     `FormattedText`, so a tie rounded differently from LLVM's
     (section 19.8) would show in both lines alike, and in `expected`
     only.
5. **`vax-library`'s `POCRTL` gains `FormattedOutput` and `OutStr`.**
   Its expected list of universal symbols grows by theirs, and `Out`'s
   and `Err`'s removed `Field` is a local procedure and was never
   universal.

### 19.10 FormattedOutput and OutStr: done

- *Done* (section 19.9, proposals 1 to 5, 2026-10-13):
  - `FormattedOutput.Mod` is `rtl/llvm`'s procedures over `LineOutput`,
    with the stream as the first parameter. Its local `Field` is the one
    `Out` and `Err` each had, with n a `HUGEINT`, as on LLVM.
  - `Out` and `Err` call it for everything but `IsConsole`. Their
    interfaces are unchanged, but their keys are new, since a symbol
    file lists its module's imports.
  - `OutStr.Mod` is `rtl/llvm`'s, plus one comment line saying it is a
    copy. `vax-outstr` checks that it is otherwise the same.
- *Not done as proposed*: the expected digits of F's and G's largest
  values (proposal 4) come from poc's LLVM build of the same program, with
  the two values made from their IEEE 754 bits, since IEEE single and
  double hold them exactly: (1 - 2^-24) * 2^127 is `7EFFFFFFH`, and
  (1 - 2^-53) * 2^1023 is `7FDFFFFFFFFFFFFFH`. That build gives the
  layout as well as the digits. Python's exact fractions confirm the
  digits, 1.70141173E+38 and 8.9884656743115785D+307.
- *Fixtures.*
  - `vax-outstr`, new. `test.sh` makes `OutStrUse.mod` from
    `llvm-outstr`'s `outstr.mod` with `awk`, so a change to that program
    reaches it. Its `guest-run.expected` is `llvm-outstr`'s output with
    the bit-pattern lines replaced, and the pair check runs on that
    file.
  - `Out` and `Err` now import `FormattedOutput`. So the 25 fixtures
    that send `FormattedText.mar` also send `FormattedOutput.mar`, and
    their guest procedures delete its object.
    - `vax-out`, `vax-err` and `vax-modules-commands` compare it in a
      new expected copy, `expected-vax-FormattedOutput.mar`, and their
      changed `Out` or `Err` too.
    - Their main modules, and `Greeter`, differ only in `Out`'s or
      `Err`'s key.
  - `vax-library`'s `POCRTL` has 15 modules and makes 299 symbols
    universal, 19 more.

### 19.11 In, InStr and FormattedInput: proposals

The sixth group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `In`, `InStr` and `FormattedInput`. On LLVM they are:
- `FormattedInput` (internal) recognizes the tokens, over an abstract
  `Source` of characters. It converts a real numeral with C's `strtof`
  and `strtod`.
- `In` reads standard input through C's `getchar`, one character ahead,
  but not past a line end until the next character is wanted. It reads
  `Real` and `LongReal` as a whole line.
- `InStr` reads a string through `FormattedInput`'s `StringSource`. It is
  plain Oberon, and its `s-` is a read-only parameter.

What VMS changes:
- SYS$INPUT is records, not a stream of bytes.
- There is no `strtod`.
- `Out` keeps a line until `Ln` (section 15, proposal 8). So a prompt
  written without `Ln`, as in `Out.String("Count? "); In.Int(n)`, is not
  on the terminal when the program waits for input. On LLVM `Out` is
  unbuffered and the prompt shows.

**Approved by the user, 2026-10-13**, all five as written.

1. **`In` reads SYS$INPUT through `Platform.Read(StdIn)`, not through a
   new `LineInput`.**
   - `Platform` already reads SYS$INPUT a record at a time (RMS `$GET`)
     and gives an LF after each record (section 19.1). It reads the next
     record only when a byte past the LF is asked for, so a program that
     prompts for a line does not wait for the following one. `In`'s
     `StandardInput` asks it for one byte at a time, where `rtl/llvm`'s
     calls `getchar`.
   - Everything else in `In` is `rtl/llvm`'s text: the one character
     read ahead, the state at a line end, and `Done`. The end of the file
     (`RMS$_EOF`, Ctrl/Z at a terminal), or a read that fails, is the end
     of the input, as `getchar`'s -1 is.
   - Since `Platform.Read(StdIn)` and `In` read the same records, a
     program can use both without losing input.
   - The cost is that a program using `In` contains `Platform`. The
     alternative is the inventory's own `LineInput`: a second reader of
     SYS$INPUT, with its own RMS stream, buffer and MACRO-32 routine.
   - Inside a record, a CR is an ordinary character. `Line` still drops
     a CR just before the LF, as on LLVM, but a record does not end in
     one.
2. **A prompt: what `Out` holds of an unfinished line is written as
   `$GET`'s prompt when SYS$INPUT and SYS$OUTPUT are both terminals.**
   - RMS writes the prompt buffer (`RAB$L_PBF`, `RAB$B_PSZ`, with
     `RAB$V_PMT` in `RAB$L_ROP`) to the terminal before a `$GET`, as it
     stands: "to perform any carriage control on the terminal, you must
     insert the appropriate carriage control characters into this
     character string" (RMS 5.0, sections 7.13 and 7.14).
   - A new `PocRtl.mar` routine, `POC_INPUT_GET`, is `POC_FILE_GET` with
     the prompt. It needs no change to `LineOutput`, since
     `POC_LINES_REGISTER` already gives the runtime the address of
     `Out`'s line and its length (section 15, proposal 8). If the length
     is between 1 and 254, the prompt is a line feed and then the line,
     the line feed taking the place of the one that starts a record
     written to the terminal. The routine then sets the length to 0, so
     the text is not written again. A longer line is left as it is.
   - `Platform` calls `POC_INPUT_GET` for StdIn, and only when
     `IsConsole(StdIn)` and `IsConsole(StdOut)` were both TRUE when it
     opened SYS$INPUT. Otherwise it calls `POC_FILE_GET`, and `Out`'s
     line stays where it is and is written by the next `Ln`. RMS ignores
     a prompt for a device that is not a terminal, so taking the line
     would lose it. Files read by name are unchanged.
   - What the terminal shows is checked by hand in a telnet session:
     the prompt, the echo of what is typed, and where the next line of
     output starts. The line feed in front is changed if that shows it
     is wrong.
   - Only `Out`'s line is a prompt: an unfinished line of `Err`'s still
     waits for its `Ln`.
   - The part-line `Flush` to a terminal, for `VT100`, stays in that step
     (section 19.7, proposal 3).
3. **`rtl/vax/FormattedInput.Mod` is `rtl/llvm`'s, but `Real` and
   `LongReal` convert by `DecimalToReal`.**
   - `Numeral` is unchanged: [+-] digits [. digits] [E|D [+-] digits],
     at most `maxNumber` characters, with the D written as E.
     `DecimalToReal` takes the numeral without its sign (section 19.7,
     proposal 4), so `Real` and `LongReal` pass what follows a sign and
     negate the result after a "-".
   - The value is the nearest F or G value, ties to even, as `strtof`'s
     and `strtod`'s is the nearest IEEE value.
   - Beyond the largest value, the result is the largest, with `Done`
     TRUE, where `strtod` gives an infinity and `Done` is TRUE. This is
     what `Reals.Ten`, and `Files` reading an IEEE infinity, already do
     (sections 19.3 and 19.7).
   - Below the smallest value, the result is the nearer of 0 and the
     smallest. The VAX has no subnormals.
   - `Source`, `StringSource` and every other token are the same text.
4. **`rtl/vax/InStr.Mod` is `rtl/llvm`'s, unchanged.** It is a copy with
   one comment line saying so, and a fixture compares the two, as for
   `OutStr` (section 19.9, proposal 3).
5. **Fixtures on the guest, each program run with SYS$INPUT defined as its
   input file** (`DEFINE/USER SYS$INPUT`). The input files go by FTP in
   ASCII mode, so each line is a record.
   - `vax-in`, new: `llvm-in`'s `intest.mod` and `input.txt`, under `-O2`
     as on LLVM. It must print `llvm-in`'s `expected` output, which voc
     agrees with.
     - A second program, `prompt.mod`, writes `Out.String("count? ")`,
       reads `In.Int`, then writes the number and `Ln`. With SYS$INPUT a
       file, the prompt must stay in `Out`'s line: "count? 42" on one
       line (proposal 2).
   - `vax-in-extra`, new: `llvm-in-extra`'s `inextra.mod`, under `-O2`.
     - Its input is `llvm-in-extra`'s, without the two lines that end in
       CR LF, since a VMS record has no line-end characters.
     - Its lines that print an integer or a token are `llvm-in-extra`'s.
     - Its lines that print a real print its bits in hex, which are F's
       and G's on the VAX. A generator writes them from the formats'
       definitions and Python's exact fractions, as `vax-reals-module`'s
       does (section 19.8). This includes 1.7976931348623157E308, which
       becomes G's largest value, and 4.9E-324, which becomes 0.
   - `vax-instr`, new: `llvm-instr`'s `instr.mod`, as `InStrUse.mod` since
     VMS does not tell `instr` from `InStr`, under `-O2` and `-OC`. It is
     run with "in" and with "instr" as its foreign command's argument
     (section 19.5). The two must read the same tokens, as `llvm-instr`
     checks, and the output must be `llvm-instr`'s `expected`. Its
     `test.sh` also compares `InStr.Mod` with `rtl/llvm`'s.
   - `vax-platform-files`, the one fixture that reads SYS$INPUT with
     `Platform`, keeps its output. Under `tools/vax-do` its SYS$INPUT is
     the command procedure, not a terminal (its check 61), so it still
     reads through `POC_FILE_GET`.
   - `vax-library`'s `POCRTL` gains `FormattedInput`, `In` and `InStr`.
   - The four expected copies of `Platform.mar` change where StdIn is
     opened and read: in `vax-platform`, `vax-files`, `vax-command-line`
     and `vax-modules-commands`. `Platform`'s interface is unchanged, so
     its key is too, and no importer's `.mar` changes.

### 19.12 In, InStr and FormattedInput: done

- *Done* (section 19.11, proposals 1 to 5, 2026-10-13):
  - `In.Mod` is `rtl/llvm`'s, but `ReadChar` reads one byte at a time
    with `Platform.Read(StdIn)`. Anything but one byte read is the end of
    the input.
  - `PocRtl.mar`'s new `POC_INPUT_GET` gives `$GET` `Out`'s unfinished
    line as its prompt, after a line feed, and empties that line.
    `Platform` calls it for StdIn when `promptInput` is set: SYS$INPUT
    and SYS$OUTPUT were both terminals when StdIn was opened.
  - `FormattedInput.Mod` is `rtl/llvm`'s, but `Real` and `LongReal` set a
    sign aside and convert the rest with `DecimalToReal`.
  - `InStr.Mod` is `rtl/llvm`'s, plus one comment line saying it is a
    copy.
- *Checked by hand* (proposal 2): `In` reads with the prompt in a telnet
  session of POC's own, a `TN` terminal, driven by an expect script.
  The program wrote "a line before" and `Ln`, then "count? " and read an
  integer, then "name? " and read a word. The terminal showed:

      a line before
      count? 42
      got 42
      name? world
      hello, world

  Each prompt was on the screen before the read, the typed text was
  echoed after it, and the next line of output started below. So the
  line feed in front is right as proposed.
- *Not done as proposed*: `vax-in-extra`'s input keeps `llvm-in-extra`'s
  two lines that end in CR LF, with the CRs removed, where proposal 5
  left them out. `inextra` reads its input line by line, so leaving them
  out would move every later read to another line. With the CRs removed,
  "windows line" is read as it is on LLVM, and the empty line is the
  `LongReal` that is not done, as the line holding only a CR is on LLVM.
- *Fixtures.*
  - `vax-in`, new: `intest` prints `llvm-in`'s `expected` on the guest,
    and `prompt` prints "count? 42" with SYS$INPUT a file.
  - `vax-in-extra`, new: its `generate.py` writes `guest-run.expected`
    from `llvm-in-extra`'s `expected` and input. It models how `In` reads
    a real, converts the value as `DecimalToReal` does, and prints F's and
    G's words as `Out.Hex` shows them. Each VAX pattern is the IEEE one
    with the exponent field 2 larger, but at the range's edges:
    1.7976931348623157E308 is G's largest value, `FFFFFFFFFFFF7FFF`,
    and 4.9E-324 is 0.
  - `vax-instr`, new: `InStrUse` with "in" and with "instr", under `-O2`
    and `-OC`, prints `llvm-instr`'s `expected` and the `In` part of it.
    Its `test.sh` also checks that `InStr.Mod` is `rtl/llvm`'s.
  - The four expected copies of `Platform.mar` change in `OpenInput`,
    `NextRecord` and the new variable. Every other difference is a line
    number or a renumbered label. `Platform`'s key is unchanged.
  - `vax-library`'s `POCRTL` has 18 modules and makes 350 symbols
    universal, 51 more.

### 19.13 Strings: proposals

The seventh group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `Strings`. `rtl/llvm`'s is plain Oberon, apart from
`StrToReal` and `StrToLongReal`. Those find the numeral at the start of
`s` (`Numeral`: blanks, [+-] digits [. digits] [E|D [+-] digits], at most
`maxNumeral` = 511 characters, the letter written as E) and hand it to C's
`strtof` or `strtod`. A string with no numeral gives 0, and one too long
leaves the variable alone.

**Approved by the user, 2026-10-13**, all three as written.

1. **`rtl/vax/Strings.Mod` is `rtl/llvm`'s, but `StrToReal` and
   `StrToLongReal` convert by `DecimalToReal`.**
   - As in `FormattedInput` (section 19.11, proposal 3), the sign that
     `Numeral` copies is set aside. The rest goes to `ToReal` or
     `ToLongReal`, and the result is negated after a "-". A local
     procedure does this, as `FormattedInput`'s `Unsigned` does, rather
     than `Strings` importing `FormattedInput`.
   - The value is the nearest F or G value, ties to even, the largest
     beyond the range, and the nearer of 0 and the smallest below it.
     This is `FormattedInput`'s rule. `strtod` gives an infinity, or a
     subnormal, there.
   - A numeral of up to 511 characters is within what `DecimalToReal`
     reads: it keeps 800 significant digits, and past them only whether
     any is nonzero.
   - Everything else is the same text. The header comment's account of
     the conversions says `DecimalToReal` where it says libc.
   - The other way to set the sign aside is in `DecimalToReal` itself,
     which would then take a sign for `FormattedInput` and `Strings`
     alike. That changes a reviewed module that `Reals` also uses, so it
     is not proposed.
2. **Fixture `vax-strings-module`, new, on the guest under `-O2`, as the
   LLVM fixtures are built.** `vax-strings` is already the backend's
   fixture for string operations.
   - `llvm-strings`' `stringstest.mod` must print `llvm-strings`'
     `expected`, which voc agrees with. Its reals are printed by
     `Out.Real` and `Out.LongReal` in decimal, and are the same on the
     VAX.
   - `llvm-strings-extra`'s `stringsextra.mod` prints that fixture's
     `expected`, except for the lines of `Numbers` that print a real's
     bits as a decimal integer (`SYSTEM.VAL(HUGEINT, x)`, or `LONGINT`
     for a `REAL`). Those are F's and G's words on the VAX.
   - A `generate.py` writes them as `vax-in-extra`'s does (section 19.12).
     It takes each numeral as `Numeral` does and converts it as
     `DecimalToReal` does, keeping `stringsextra`'s 42 and 7 where no
     numeral is read or it is too long. 1.7976931348623157E308 becomes
     G's largest value, 4.9E-324 becomes 0, and 2.2250738585072014D-308,
     which is IEEE's smallest normal value, is an ordinary normal G
     value.
   - `stringsextra`'s 40000-character array and its lengths past 32767
     are the same under `-O2` on both, since `INTEGER` is 16 bits there.
3. **`vax-library`'s `POCRTL` gains `Strings`.** No other module imports
   it, so no other fixture changes.

### 19.14 Strings: done

- *Done* (section 19.13, proposals 1 to 3, 2026-10-13): `Strings.Mod` is
  `rtl/llvm`'s, but `StrToReal` and `StrToLongReal` set the sign aside
  (`Unsigned`, as in `FormattedInput`) and convert the rest by
  `DecimalToReal`. It imports `DecimalToReal` in place of `SYSTEM`, which
  it then no longer needs.
- *Fixtures.*
  - `vax-strings-module`, new: `stringstest` prints `llvm-strings`'
    `expected` on the guest. `stringsextra` prints `llvm-strings-extra`'s,
    but for `Numbers`' bit patterns.
  - Its `generate.py` writes those from the numerals in
    `stringsextra.mod`, read as `Numeral` reads them and converted as
    `DecimalToReal` does, with each `x := 42` in its place. Each VAX
    pattern is the IEEE one with the exponent field 2 larger, but at the
    range's edges: 1.7976931348623157E308 is G's largest value (-32769 as
    a `HUGEINT`), and 4.9E-324 is 0. 2.2250738585072014D-308 is 2^-1022,
    a normal G value (48).
  - `vax-library`'s `POCRTL` has 19 modules and makes 363 symbols
    universal, 13 more.

### 19.15 Math and MathL: proposals

The eighth group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `Math` and `MathL`. The inventory decided that they go
over `MTH$`: `MTH$`'s F routines for `Math`, its G ones for `MathL`, with
`MTH$`'s signalled errors mapped to voc's codes (proposal 5). `rtl/llvm`'s
modules are calls of libm's double functions with error checks around
them. A domain error is checked before the call (`ln` of a number <= 0,
`arcsin` beyond 1, ...). An overflow is seen in the result, an infinity.
The real-number properties (`exponent`, `fraction`, `scale`, `ulp`,
`succ`, `pred`) come from libm's `logb`, `ldexp` and `nextafter`. The
sources here are the 5.4 MTH$ manual (`AA-LA72B`; we do not have the 5.5
edition), the 5.0 OTS$ manual (`AA-LA73A`) and the 5.0 LIB$ manual
(`AA-LA76A`).

What `MTH$` does with an error (MTH$ 1.4): it signals the condition, as
SEVERE, by `LIB$SIGNAL`, and with no handler the image exits with the
message. Overflow is `MTH$_FLOOVEMAT`, for example `MTH$GEXP` above about
709.089 (MTH$ manual, MTH-66). Underflow is signalled only if the
caller has enabled floating underflow, which poc does not, and the
result is 0.
`MTH$` has no `asinh`, `acosh`, `ldexp`, `logb` or `nextafter`, and no
power. Power is `OTS$`'s: `OTS$POWRR` and `OTS$POWGG` (F and G to an F
or G power) and `OTS$POWRJ` and `OTS$POWGJ` (to a longword power). Their
arguments go by value (OTS$ manual, OTS-67 to OTS-87).

A first look on the guest, 2026-10-14, with a MACRO routine that
establishes `LIB$SIG_TO_RET` and calls `MTH$` routines from a table:

- A signal comes back as the routine's status: `MTH$GEXP(709.5)` gives
  `MTH$_FLOOVEMAT` (`%X001682C4`), `MTH$GLOG(0)` gives `MTH$_LOGZERNEG`
  (`%X0016829C`), and nothing is printed. `LIB$SIG_TO_RET` unwinds to the
  caller of the routine that established it, with the condition in `R0`
  (LIB$ manual, `LIB$SIG_TO_RET`).
- `MTH$` reduces a large argument accurately. `MTH$GSIN` of 2^60 and of
  1.0D300, `MTH$GCOS` of 1.0D22 and `MTH$SIN` of 2^40 and of 1.0E30 agree
  with Python's values to every digit printed. `MTH$GTAN` at the double
  nearest pi/2 is 1.633123935319537D16, as libm's.
- `MTH$GEXP(709)` is 8.2184074615549724D307, `MTH$EXP(88)` is
  1.65163627E38, and `MTH$GEXP(-720)` and `MTH$EXP(-100)` are 0 with no
  signal.

**Approved by the user, 2026-10-14**, all five as written.

1. **Math and MathL call MTH$ and OTS$ through one new routine,
   `POC_MATH(function, x, y, result)`, in `PocRtl.mar`.**
   - It establishes `LIB$SIG_TO_RET` as its own handler (`MOVAB
     G^LIB$SIG_TO_RET, (FP)`). Then it calls the routine numbered
     `function` in a table, with `x` and `y` given to it as that routine
     takes them, and stores its value in `result`. `R0` is 1, or else the
     condition that the routine signalled.
   - The table has one entry per routine:
     - F: `MTH$SQRT`, `SIN`, `COS`, `TAN`, `ASIN`, `ACOS`, `ATAN`,
       `ATAN2`, `EXP`, `ALOG`, `SINH`, `COSH`, `TANH`, `ATANH`, and
       `OTS$POWRR` and `OTS$POWRJ`.
     - G: `MTH$GSQRT` to `MTH$GATANH`, and `OTS$POWGG` and `OTS$POWGJ`.
   - Each entry gives the routine's address, how many arguments it takes
     and how (by reference for `MTH$`, by value for `OTS$`), and the size
     of its result (a longword for F, a quadword for G). The table is in
     `POC_ADDR`, since it holds addresses (section 18.5).
   - `Math` and `MathL` declare it `["VMS"]`, with `x`, `y` and `result`
     as `VAR` parameters and `function` as a `SYSTEM.INT32` value. That
     is all section 7's lowering needs, and it is the same under `-O2`
     and `-OC`.
   - The other way is for `Math` to establish a handler itself. That
     needs step 5's mechanisms, or step 6's handlers from Oberon, as
     the inventory said. This routine does the work now in `PocRtl`, and
     no other module needs it.
   - `tools/vax-runtime-stub.mar` gets a stand-in for it in the same
     change (the lesson of d012626).
2. **Errors as on LLVM: what is an error, what comes back, and the code
   given to `ErrorHandler` are those of `rtl/llvm`'s table.**
   - Every domain error is checked in Oberon before the call, as on
     LLVM, so `MTH$` is never given an argument it would signal for.
   - What is left is overflow: `exp`, `power`, `ipower`, `sinh`, `cosh`
     and `tan` can signal `MTH$_FLOOVEMAT` (or `OTS$`'s `SS$_FLTOVF` or
     `MTH$_UNDEXP` for 0 to a negative power, in `ipower`). A failing
     status from `POC_MATH` reports `Overflow` and gives `large`, or
     `-large` where the true result is negative (`sinh` of a negative
     number, `ipower` of a negative number to an odd power).
   - Underflow is as on LLVM: a result of 0 from a nonzero argument
     reports `Underflow` (`exp`, `power`). The VAX gives 0 there without
     a signal.
   - `sin`, `cos` and `tan` give `MTH$`'s answer for every argument,
     which keeps LLVM's promise (vishap-bugs 48).
3. **What MTH$ lacks is written in Oberon.**
   - `arcsinh` is ln(|x| + sqrt(x^2 + 1)) with x's sign, or ln(|x|) +
     ln 2 where x^2 would overflow, and x itself where |x| is so small
     that x^2 vanishes beside 1.
   - `arccosh` is ln(x + sqrt(x^2 - 1)), or ln(x) + ln 2 for a large x.
   - The properties come from F's and G's own fields. `SYSTEM.VAL`
     gives the bits as a `LONGINT` (F) or a `HUGEINT` (G). Their low 16
     bits are the first word in memory, which holds the sign and the
     exponent: 8 bits from bit 7 for F, and 11 bits from bit 4 for G.
     `exponent` is the field less 129 for F, and less 1025 for G.
     `fraction` and `scale` set the field, with the range checked first.
     `ulp` is 2^(exponent - places + 1).
   - `succ` and `pred` step one unit in the last place, a half unit
     where they cross a power of 2 downward. The formats have no
     denormals, so `succ(0)` is `small` and `pred(0)` is `-small`, and
     `succ(-small)` is 0. `scale` below the range gives 0 with no error,
     as LLVM's `scale` to zero does.
   - `Finite` goes: the formats have no infinities or NaNs. `round`,
     `fcmp`, `sign`, `log` and `sincos` keep `rtl/llvm`'s text.
4. **The interface's constants are F's and G's**, in `rtl/llvm`'s
   convention (1 <= |fraction(x)| < 2).

   | Constant | `Math` (F) | `MathL` (G) |
   |---|---|---|
   | `places` | 24 | 53 |
   | `large` | `MAX(REAL)`, 1.7014117E38 | `MAX(LONGREAL)`, 8.98846567431158D307 |
   | `small` | 2^-128, 2.9387359E-39 | 2^-1024, 5.562684646268003D-309 |
   | `expoMax` | 126 | 1022 |
   | `expoMin` | -128 | -1024 |

   `pi`, `e`, the error codes, `ErrorHandler`, `err` and `ClearError`
   are unchanged. `TanhMax` is still `arctanh(1 - 2^-places)`.
5. **Fixtures, on the guest under `-O2`, as the LLVM ones are built.**
   - `vax-math-module`, new: `llvm-math`'s `mathtest.mod` and
     `llvm-mathl`'s `mathltest.mod`, which check every function against
     Python's values within 1.0E-5, must print those fixtures'
     `expected`. `test.sh` copies them and changes only the `expoMax` and
     `expoMin` checks to proposal 4's values, with `sed`. Those are the
     only lines that state IEEE's ranges.
   - `vax-math-extra`, new, in place of `llvm-math-extra`, which checks
     IEEE's bit patterns, denormals and infinities. It checks:
     - F's and G's bit patterns of `large` and `small`;
     - `succ` and `pred` at 0, at +-1, at +-`small` and at +-`large`;
     - `exponent` and `fraction` at both ends of the range;
     - `scale` beyond the range both ways;
     - the overflows of item 2, each with its code and its sign;
     - the probe's large arguments to `sin`, `cos` and `tan`, against
       Python's values;
     - `arcsinh` and `arccosh` at small, ordinary and large arguments.
   - `vax-library`'s `POCRTL` gains `Math` and `MathL`.

### 19.16 Math and MathL: done

- *Done* (section 19.15, proposals 1 to 5, 2026-10-14):
  - `PocRtl.mar`'s `POC_MATH` dispatches on `function` by `CASEL`, each
    arm pushing the arguments as its routine takes them and calling it
    by `G^`. It has no table of addresses, so it needs nothing in
    `POC_ADDR` and stays position independent. `tools/vax-runtime-stub.mar`
    has a stand-in for it.
  - `rtl/vax/Math.Mod` and `MathL.Mod` keep `rtl/llvm`'s interface, its
    table of errors and its text where nothing VAX-specific is involved.
    Each function checks its domain, calls `POC_MATH`, and turns a
    failing status into `Overflow` and +-`large`. `ipower(x, 0)` is 1
    without a call, since `OTS$` signals for 0^0.
  - `arcsinh` and `arccosh` use fdlibm's forms: ln(2|x| + ...) for
    ordinary arguments, ln|x| + ln 2 beyond 2^(places/2), and ln(1 + u)
    as ln(w) * u / (w - 1) near 0, which keeps u's digits.
  - The properties read and set the exponent field of the first word.
    `succ` and `pred` step the magnitude made from the words in the other
    order. `ulp` is 0 where the unit is below the range, as `scale` is.
  - `MathL.small` is written `5.5626846462680035D-309`. The backend
    writes a literal's numeral as it is (`RealConstant`), and IEEE's
    shortest numeral for 2^-1024, `5.562684646268003D-309`, is just below
    it, which MACRO makes 0.
- *Fixtures.*
  - `vax-math-module`, new: `mathtest` and `mathltest` print `llvm-math`'s
    and `llvm-mathl`'s `expected` on the guest, with only the `expoMax`
    and `expoMin` checks changed by `sed`.
  - `vax-math-extra`, new: the checks of what differs from LLVM. Among
    them, the overflows of `exp`, `sinh`, `cosh`, `power` and `ipower`
    caught as `Overflow` with their sign, and `ipower(2, -1080)` 0 with
    no error.
  - `vax-library`'s `POCRTL` has 21 modules and makes 431 symbols
    universal, 68 more. Its `test.sh` now lists `rtl/vax`'s modules in
    C's order (`LC_ALL=C ls`). The glob followed the locale, which put
    `MathL.Mod` before `Math.Mod` on atla and after it on the BSD hosts.

### 19.17 Args and VT100: proposals

The ninth group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `Args` and `VT100`.
- `rtl/llvm`'s `Args` is voc's interface over `Modules`' command line and
  `Platform`'s environment, which `rtl/vax` has had since sections 19.1
  and 19.5.
- `rtl/llvm`'s `VT100` writes each escape sequence through `Out` in one
  piece. On LLVM `Out` writes at once, so a sequence reaches the screen
  when it is sent. On VMS `Out` keeps a line until `Ln` (section 15), and
  `Out.Flush` does nothing. A cursor movement would wait for the end of
  the line.
- The inventory decided that `Out.Flush` writes a part line to a
  terminal without ending the record, and keeps doing nothing to a file,
  so that records stay whole (proposal 6).

What VMS gives for that: a terminal write by `$QIO` with
`IO$_WRITEVBLK` whose `P4`, the carriage control, is 0 writes the buffer
with no carriage control before or after it (5.4 I/O manual, part 1,
8.4.2.2). A record that `LIB$PUT_OUTPUT` writes to a terminal is a line
feed, the text and a carriage return, which is why `POC_INPUT_GET`'s
prompt starts with a line feed (section 19.12). Checked on the guest,
2026-10-14: `DEFINE ARGSTEST_EMPTY ""` fails with
`%SYSTEM-F-IVLOGNAM`, so a logical name cannot translate to an empty
string.

**Approved by the user, 2026-10-14**, all four as written.

1. **`rtl/vax/Args.Mod` is `rtl/llvm`'s, unchanged.** `Get`, `GetInt`,
   `Pos`, `argc` and `argv` are `Modules`', and `GetEnv` and `getEnv` are
   `Platform`'s, which translate a logical name (section 19.1). A
   variable set but empty, which `getEnv` tells from one not set, cannot
   happen on VMS.
2. **`Out.Flush` writes Out's line so far to a terminal, without ending
   it, by a new `PocRtl` routine, `POC_FLUSH_OUTPUT`.**
   - When SYS$OUTPUT is a terminal (`$GETDVIW`, as `Out.IsConsole`
     asks), it writes Out's line (`POC_LINES`) by `$QIOW` with
     `IO$_WRITEVBLK` and `P4` 0. The channel is `$ASSIGN`ed to SYS$OUTPUT
     on the first flush.
   - If the line has not been started on the terminal, a line feed goes
     first, as before a record. Out's line is then empty, and a flag in
     `PocRtl` says that the terminal's line is open.
   - While the line is open, whatever ends it writes the rest the same
     way and then a carriage return, which leaves the terminal as a
     record would, and clears the flag. That is `Ln` (`POC_PUT_LINE`), or
     a line longer than `LineOutput`'s 1024 characters, or the exit
     handler (`POC_LINES_EXIT`).
   - `POC_INPUT_GET`'s prompt leaves out its line feed while the line is
     open, so a prompt written in pieces with `Flush` between them
     stays on one line. Reading ends the line, as the terminal's echo of
     the return does, so the flag is cleared.
   - To anything but a terminal `Flush` does nothing, as now, and the
     flag is never set, so a file's records are what they are now.
   - `Err.Flush` keeps doing nothing. `VT100` writes through `Out`, and
     SYS$ERROR's lines go by RMS (section 15).
3. **`rtl/vax/VT100.Mod` is `rtl/llvm`'s, but each procedure that sends a
   sequence calls `Out.Flush` after it**, so that the sequence reaches a
   terminal when it is sent, as on LLVM. Text the program wrote with
   `Out` before it goes with it, in order. To a file the output is the
   records it is now. The header comment says so. VT100 and later DEC
   terminals take ECMA-48's sequences as they are.
4. **Fixtures, on the guest.**
   - `vax-args`, new: `llvm-args`' `argstest.mod` built under `-O2`, run
     as a foreign command with `"alpha" "" 42 -7 x9`. `alpha` is quoted,
     since DCL makes an unquoted parameter upper case
     (`vax-command-line`). `ARGSTEST_SET` is defined as a process logical
     name and the others are not defined. It must print `llvm-args`'
     `expected`, except that the set-but-empty variable's lines are "not
     set" ones (proposal 1). A `generate` step is not needed: those two
     lines are written in the fixture's `guest-run.expected`.
   - `vax-vt100`, new: `llvm-vt100`'s `vt100same.mod` and `vt100diff.mod`
     under `-O2` and `-OC`, their output to a file. They must write
     `llvm-vt100`'s bytes, as `cat -v` shows them. Where a program ends
     a line on LLVM, its record ends there on VMS, and output not ended
     by `Ln` is ended by the exit handler as a record of its own.
   - `Flush` on a terminal cannot be a fixture, since `tools/vax-do`'s
     output is a file. It is checked by hand in a telnet session as POC,
     as the prompt was (section 19.12), with a program that writes part
     of a line, moves the cursor with `VT100`, flushes, prompts with
     `In`, ends a line with `Ln`, and ends with a line not ended. The
     session's bytes are recorded in section 19.18.
   - `vax-library`'s `POCRTL` gains `Args` and `VT100`, and
     `tools/vax-runtime-stub.mar` gets a stand-in for `POC_FLUSH_OUTPUT`.

### 19.18 Args and VT100: done

- *Done* (section 19.17, proposals 1 to 4, 2026-10-14):
  - `rtl/vax/Args.Mod` is a copy of `rtl/llvm`'s.
  - `PocRtl.mar`'s `POC_FLUSH_OUTPUT` asks once whether SYS$OUTPUT is a
    terminal (`POC_IS_TERMINAL`), and if it is, `$ASSIGN`s a channel to
    it. `POC_TERMINAL_WRITE` writes by `$QIOW` with `IO$_WRITEVBLK` and
    `P4` 0. `POC_OPEN_LINE` is the flag.
  - `POC_PUT_LINE`, on an open line, writes the text and a carriage
    return to the terminal instead of calling `LIB$PUT_OUTPUT`.
    `POC_LINES_EXIT` calls it for an open line even when Out's line is
    empty, so the line is ended.
  - `POC_INPUT_GET`, on an open line, makes Out's line of 1 to 255
    characters the prompt without a line feed, or writes a longer one by
    `POC_FLUSH_OUTPUT`, and clears the flag.
  - `Out.Flush` calls `POC_FLUSH_OUTPUT`. `rtl/vax/VT100.Mod` is
    `rtl/llvm`'s with `Out.Flush` after `Send`, `SendNumber`,
    `SendNumbers` and `SetAttr`'s sequences; `Reset` ends its line with
    `Ln` already.
- *Fixtures.*
  - `vax-args`, new: `argstest` prints `llvm-args`' `expected` on the
    guest, but "empty FALSE [unchanged]". `x9` is quoted as well as
    `alpha`, since DCL would make it `X9`.
  - `vax-vt100`, new: `vt100same` and `vt100diff` under `-O2` and `-OC`
    write `llvm-vt100`'s bytes on the guest. `test.sh` takes each
    model's lines from `llvm-vt100`'s `expected`, with `cat -v`'s `^[`
    and `^V` made ESC and SYN again, so no control character is
    committed.
  - `vax-out`'s and `vax-modules-commands`' `expected-vax-Out.mar`: `Flush`
    calls `POC_FLUSH_OUTPUT`, and the line numbers after it move.
  - `vax-library`'s `POCRTL` has 23 modules and makes 468 symbols
    universal, 37 more. `tools/vax-runtime-stub.mar` has a stand-in for
    `POC_FLUSH_OUTPUT`.
- *Checked by hand* (2026-10-14), in a telnet session as POC driven by
  expect, its bytes logged, with a program that flushes part of a line,
  moves the cursor with `VT100`, prompts in pieces and ends with a line
  open. `^M` is a carriage return; each line here ended with a line
  feed:

  ```
  part one part two^[[4D^[[1mB^[[0m^M
  a record^M
  count? 42^M
  ^Mgot 42^M
  name? world^M
  ^Mgot world^M
  open at the end^M
  ^MVAXASM>
  ```

  - "part one" was written by `Flush` after a line feed. " part two", the
    cursor movement and the bold B followed on the same line as `VT100`
    sent them, and `Ln` ended the line with a carriage return.
  - "name" was flushed, and "? " was then `In`'s prompt without a line
    feed, so the prompt stayed on one line.
  - The line still open when the program ended was ended by the exit
    handler, and DCL's prompt came on a new line.


### 19.19 Texts and Oberon: proposals

The tenth group in the inventory's order (`vms-module-inventory.md`,
proposal 1) is `Texts` and `Oberon`. It also takes `Platform`'s `getEnv`
on to DCL symbols, as the user asked on 2026-10-14.

`rtl/llvm`'s `Texts` imports `Files`, `Modules`, `Reals` and
`RealDigits`, which `rtl/vax` has had since sections 19.3, 19.5 and 19.8.
Three parts of it assume the LLVM targets.
- `Scan` converts a real with C's `strtof` and `strtod` (lines 195-196
  and 668-674).
- `RealBits` and `LongRealBits` (lines 825-845) read IEEE 754's sign bit,
  zero, infinity and NaN.
- `Close` keeps the old file as `<name>.Bak`, renamed with
  `Files.Rename`. `plain.Text.Bak` is not an ODS-2 name: after the type,
  a second dot starts the version (RMS, "file specification"), and `Bak`
  is not a number, so the rename fails. `Close` ignores the result, so the
  old file would stay as an older version.

`rtl/llvm`'s `Oberon` uses `Platform`'s clocks, `Modules.ArgCount`, and
`Modules.ArgVector` read as C's `argv`. Section 19.5 made `ArgVector` that
on VMS too (proposal 8).

VAX C's `getenv` (VAX C RTL Reference, March 1987, 11.2.5) looks a name
up in this order.
1. Its environment array: `HOME`, `TERM`, `PATH` and `USER`.
2. A logical name, in the standard tables in order.
3. A CLI symbol, through DCL.

It returns NULL when none of them has the name. `LIB$GET_SYMBOL` (5.0
LIB$ manual, LIB-218 to LIB-220) gives a symbol's value, local first and
then global, with a numeric symbol as decimal text. It returns
`LIB$_NOSUCHSYM` when there is no such symbol and `LIB$_NOCLI` when there
is no CLI. A symbol can be defined empty (`X == ""`), as a logical name
cannot (section 19.17).

**Approved by the user, 2026-10-14**, with no `.Bak` (proposal 1) and
without `HOME` and `USER` (proposal 3).

1. **`rtl/vax/Texts.Mod` is `rtl/llvm`'s with four changes.** The header
   comment lists them.
   - `Scan` converts a real's numeral, without its sign, with
     `DecimalToReal.ToReal` or `ToLongReal`, as `Strings` and
     `FormattedInput` do (sections 19.12 and 19.14). `Scan` already sets
     the sign itself. The `["C"]` declarations go.
     - The result is the nearest value, ties to even, as `strtof` and
       `strtod` give.
     - A numeral beyond the range gives the largest value and not
       infinity, which the VAX does not have.
   - `RealBits` and `LongRealBits` read the VAX's formats.
     - The sign is bit 15, in the first word, under both.
     - Zero is an exponent field of 0 (`Reals.Expo` and `ExpoL`). With
       the sign set, that is the reserved operand, which no value has.
     - `special` and `isNaN` are always FALSE, so `WriteSpecial`'s
       "Infinity" and "NaN" are never written. It stays, so that the rest
       stays as LLVM's.
   - `WriteRealHex` and `WriteLongRealHex` are unchanged. They give the
     value's bytes in memory order (`Reals.ConvertH`), which on the VAX
     are F_floating's and G_floating's bytes. 1.0 is `80400000` and -2.0D0
     is `20C0000000000000`, where LLVM gives `0000803F` and
     `00000000000000C0`.
   - `Close` keeps no `.Bak` on VMS. `Files.Register` already makes the
     new file a new version, and the old one stays as the version below
     it (section 19.3, `Register`; section 19.1, proposal 8). That is
     what VMS keeps instead of a backup, and what PURGE clears.
     - The alternative is a name of VMS's own, such as
       `<name>_BAK`, with the rename's result still ignored.
2. **`rtl/vax/Oberon.Mod` is `rtl/llvm`'s, unchanged.** `Par.text` holds
   the arguments as section 19.5's `ArgVector` gives them:
   - quotes are removed;
   - quoted text keeps its case;
   - unquoted text is upper case, as DCL makes it.
3. **`Platform.getEnv` and `GetEnv` look up a DCL symbol when there is no
   logical name**, through a new `PocRtl` routine, `POC_GET_SYMBOL`,
   which calls `LIB$GET_SYMBOL`. `Args.GetEnv` and `getEnv` are
   `Platform`'s, so they follow.
   - The order is VAX C's, without its environment array: logical names
     first, as now (`POC_TRNLNM`, section 19.1), then a symbol, local
     before global. `LIB$_NOSUCHSYM`, `LIB$_NOCLI` or any other failure
     is "not set".
   - A symbol defined empty is set but empty. `getEnv` returns TRUE with
     an empty value, as on Unix, and the case section 19.17 said could
     not happen on VMS now can.
   - A value longer than the caller's array is cut, as a logical name's
     is now.
   - VAX C's four environment names are left out. `HOME` would be
     `SYS$LOGIN`'s translation, `USER` the user name (`$GETJPI`,
     `JPI$_USERNAME`) and `PATH` the default device and directory. The
     manual does not say what form `TERM` takes. A program that wants
     them can ask for `SYS$LOGIN` itself. They can be added later if a
     program needs them.
4. **Fixtures, on the guest.**
   - `vax-texts`, new: `llvm-texts`' `texts.mod` under `-O2`.
     - It must print `llvm-texts`' `expected`, except for the lines that
       show a real's bytes in hexadecimal. Those are the `bits:` part of
       the first text, and each scanned real's `x=` or `y=`. The fixture
       commits those lines as the VAX gives them, and `test.sh` takes the
       rest from `llvm-texts`' `expected`, as `vax-vt100` does. Each VAX
       line is checked by hand against the F_floating and G_floating
       formats before it is committed.
     - `elements.Text`, `plain.Text` and `lines.txt` are fetched back in
       binary and compared with what the LLVM build of `texts.mod` writes
       on the host. A text's file holds no reals, so the bytes must be
       the same. `plain.Text` must be on the guest as two versions, and
       no `.Bak` file is made.
   - `vax-oberon`, new: `llvm-oberon`'s `oberon.mod` and `beyond.mod`,
     under `-O2` and `-OC`, run as foreign commands.
     - `oberon` gets `"Name.sub" 12 """a string""" -7 / "x"`. The quotes
       keep case and give the quoted string, and it must print
       `llvm-oberon`'s `oberon` lines. If DCL does not pass a lone `/`
       through `LIB$GET_FOREIGN`, the fixture quotes it.
     - `beyond`'s argument on LLVM is 300 characters. DCL limits a
       foreign command's line to 255 characters (section 18.5), so here
       it gets 200, and its first line is `par 201`. The rest is
       `llvm-oberon`'s.
   - `vax-args` defines `ARGSTEST_EMPTY == ""` and `ARGSTEST_SYM ==
     "from a symbol"` in its procedure, after the logical names.
     - `argstest` then prints `llvm-args`' `expected` exactly. The
       "empty FALSE [unchanged]" line section 19.18 recorded goes.
     - A line is added for the symbol, so `argstest.mod` gets a VAX copy
       or a guarded line. Which is decided when it is written; I would
       rather add one variable to the shared `argstest.mod`, which LLVM
       prints as "not set".
   - `vax-platform`'s `getEnv` cases, if any read a name that could be a
     symbol on the guest, are checked so that `POC`'s own `LOGIN.COM`
     symbols cannot change them.
   - `vax-library`'s `POCRTL` gains `Texts` and `Oberon`.
     `tools/vax-runtime-stub.mar` gets a stand-in for `POC_GET_SYMBOL`.
   - The four `expected-vax-Platform.mar` files are regenerated:
     `vax-platform`'s, `vax-command-line`'s, `vax-files`' and
     `vax-modules-commands`'. Their `;;` headers are updated when the
     user has reviewed them.

### 19.20 Texts and Oberon: done

- *Done* (section 19.19, proposals 1 to 4, 2026-10-14):
  - `rtl/vax/Texts.Mod` is `rtl/llvm`'s with the four changes of
    proposal 1. `Scan` converts by `DecimalToReal.ToReal` and
    `ToLongReal`. `RealBits` and `LongRealBits` take the sign from bit 15
    and zero from the exponent field. `Close` writes the new version and
    renames nothing. The header comment lists the changes.
  - `rtl/vax/Oberon.Mod` is a copy of `rtl/llvm`'s.
  - `PocRtl.mar`'s `POC_GET_SYMBOL` calls `LIB$GET_SYMBOL` and returns the
    value's length, or -1 on any failure. `Platform.getEnv` calls it when
    `POC_TRNLNM` finds no logical name. `GetEnv` and `Args` follow.
- *Found and fixed: `Files.New("")`.* Texts' writers keep what they write
  in a file with no name, `Files.New("")`, as on LLVM. `rtl/vax`'s `New`
  stopped the program for an empty name ("file name too long",
  `HALT(99)`, status `%X1000031A`), so every Texts writer did. `New("")`
  now makes a File whose temporary file, `POC_<pid>_<n>.TMP` in the
  default directory, `Register` does not rename. It is deleted when the
  File is finalized, as an unregistered file's always was. After
  `vax-texts` ran, no `.TMP` file was left in `POC`'s directory.
- *Fixtures.*
  - `vax-texts`, new: `llvm-texts`' `texts.mod` as `TextsUse.mod`, with its
    elements naming that module. `vax-reals.sed` turns `llvm-texts`'
    `expected` into the VAX's, eight lines with a real's bytes. On the
    guest, `TextsUse` prints that, and `plain.Text`, closed twice, is two
    versions.
    - `FileBytes.mod` dumps `elements.Text`, `plain.Text` and `lines.txt`
      in hexadecimal. Those are the bytes that `TextsUse` built by poc
      for the host writes, as `od` shows them. The element names its
      module in the file, so the host build is of `TextsUse.mod` too.
  - `vax-oberon`, new: `OberonUse.mod` (`llvm-oberon`'s `oberon.mod`) and
    `beyond.mod` under `-O2` and `-OC`. They print `llvm-oberon`'s lines
    for each model, but `par 201` for `beyond`'s 200-character argument,
    which the procedure makes with `F$FAO("!199*0")`. An unquoted `/`
    reaches the program as it is.
  - `vax-args`: the procedure defines `ARGSTEST_EMPTY == ""` and the
    local `ARGSTEST_NUMBER = 12`, and `argstest` prints `llvm-args`'
    `expected`: "empty TRUE []" and "number TRUE [12]".
  - `llvm-args`' `argstest.mod` reads `ARGSTEST_NUMBER` too, which its
    `test.sh` sets to 12 for voc's build and poc's.
  - `vax-library`'s `POCRTL` has 25 modules and makes 533 symbols
    universal, 65 more. `tools/vax-runtime-stub.mar` has a stand-in for
    `POC_GET_SYMBOL`.
  - `expected-vax-Platform.mar` in `vax-platform`, `vax-command-line`,
    `vax-files` and `vax-modules-commands`: the new `.EXTERNAL` and
    `getEnv`'s symbol branch, and the line numbers after it move.
    `vax-files`' `expected-vax-Files.mar`: `New`'s branch for "" and its
    string, and the line numbers and labels after it.

## 20. Unsigned integer types on the VAX (Phase 17, after 0.6.0)

`main`'s unsigned types, `SYSTEM.CARD8`..`CARD64` and `SYSTEM.CARD`, and
the new end of every `FOR` loop (`language-extensions.md`, "Unsigned
integer types" and "FOR final value"; released in 0.6.0) came to `vax` in
the merge `2ff7cef`. The front end accepts them for the VAX as for LLVM,
but the VAX backend treats a CARD as the signed integer of its size, and
still lowers `FOR` by the report's own equivalence, so a loop up to
`MAX` of its type never ends there. `rtl/vax` has none of the runtime's
new `Card` procedures, and `vax-instr` and `vax-outstr` fail, since
`rtl/vax`'s `InStr` and `OutStr` are no longer copies of `rtl/llvm`'s.
`SYSTEM.CARD` is a `CARD32` on the VAX, addresses being longwords.
`sdloberon` declaring SDL's unsigned fields and parameters as `CARDn`
follows this, as its own step (the plan agreed with the user,
2026-10-14).

### 20.1 Proposals

**Approved by the user, 2026-10-14**, all ten as written.

1. **A CARD is zero-extended wherever it widens.** `MoveInto`, `Widen`
   and `SYSTEM.VAL` choose by the source's family: `MOVZBW`, `MOVZBL` or
   `MOVZWL` for a CARD, `CVT` for a signed integer; into a quadword, the
   low longword so, then `CLRL` of the high one in place of `ASHL #-31`.
   - This one place covers `LONG`, assignment, a CARD passed to a wider
     CARD parameter (`Out.Card(a)` of a `CARD8`), a CARD index
     (`CheckedIndex`'s `Widen` to a longword: 200 in a `CARD8` is 200,
     not -56), a `CASE` selector, `IN`, `INCL` and `EXCL`'s element, and
     the integer half of a conversion to a real (proposal 4).
   - `SYSTEM.VAL` extends by the source's family, as on LLVM:
     `SYSTEM.VAL(LONGINT, c)` of a `CARD16` is its value.
2. **Comparisons of CARDs are unsigned.** `FalseBranch` gives `BLSSU`,
   `BLEQU`, `BGTRU` and `BGEQU` for a CARD, as it does for a `CHAR`, and
   `QuadRelation` compares a `CARD64`'s high longwords unsigned too (its
   low ones already are). `Relation`, `JumpOnRelation`, `CASE`'s tests
   outside a `CASEx` table and `FOR`'s head (proposal 8) all come
   through these.
3. **`DIV` and `MOD` of CARDs are unsigned; truncation and flooring
   agree.**
   - A `CARD8` or `CARD16`: both operands zero-extended to longwords,
     `DIVL3`, and the remainder by `MULL3` and `SUBL3`, as `DivMod` does,
     without its floor correction. The values are below 2^16, so the
     signed divide is the unsigned one; the result is of the CARD's own
     size.
   - A `CARD32`: both zero-extended to quadwords and divided by
     `POC_HDIV` or `POC_HMOD`, whose 64-bit signed division is exact for
     values below 2^32; the result is the low longword. `EDIV`, the only
     divide taking a quadword, is signed in its divisor and overflows
     on a quotient of 2^31 or more, so it serves neither.
   - A `CARD64`: new runtime routines `POC_CDIV` and `POC_CMOD` in
     `PocRtl.mar`, `HDIVMOD`'s bit-by-bit division of the magnitudes, for
     which every `CARD64` is one already, without the sign handling and
     the floor.
   - A zero divisor is not checked, as for the signed types. It is the
     VAX's integer divide-by-zero trap: `DIVL3` for the narrow ones, and
     the routines' `DIVL2` by the divisor, as `HDIVMOD` does already.
4. **A CARD converted to a real is its unsigned value, rounded once.**
   - A `CARD8` or `CARD16` is zero-extended to a longword, then
     `CVTLF` or `CVTLG`.
   - A `CARD32`: `CVTLG`, which is exact, and when the longword is
     negative, `ADDG2 #4294967296.0`, which is exact too, being below 2^33;
     for a `REAL`, `CVTGF` of that, the only rounding.
   - A `CARD64`: a new routine `POC_CTOG`, `POC_QTOG` with its high
     longword read unsigned as its low one already is, then `CVTGF` for a
     `REAL`, as a `HUGEINT` is converted (rounded twice for a `REAL`, as a
     `HUGEINT` already is; section 14, item 9).
5. **Shifts.** `ASH` of a CARD is `SYSTEM.LSH` of it, as on LLVM: of its
   own type, filling with zeros (`Lsh`, which shifts a longword or a pair
   right by an arithmetic shift of 1 bit, the sign bit cleared, then the
   rest). `ShiftCount` takes a CARD count as never negative: zero-extended,
   then compared unsigned with 64, so a `CARD8` count of 200 shifts every
   bit out rather than being read as -56. `SYSTEM.ROT` is unchanged, its
   count being taken modulo the width.
6. **The checked and the identity operations.**
   - `SHORT` of a CARD with `-range-checks` traps (14) when the value is
     above the narrower type's `MAX`: `CMPx v, #MAX` and `BLEQU`, since
     `CVT`'s V is the signed test; a `CARD64` fits a `CARD32` when its
     high longword is 0. The value is then the low bytes, by `MOVx` from
     the low end, as `CVT` would give for a value that fits.
   - `CHR` of a `CARD8` always fits; `Chr`'s `TSTB` test, the signed one
     for a byte, is skipped for it. Wider CARDs keep the unsigned compare
     with 255 that `Chr` makes already.
   - `ABS` of a CARD is the value itself; unary minus is `MNEGx`, modulo
     2^n, as it is now.
7. **A CARD constant above its width's signed range is written in
   hexadecimal**, `#^XFFFFFFFF` for `MAX(SYSTEM.CARD32)`, as `HalfText`
   already writes `MIN(LONGINT)` as `^X80000000`, so that MACRO reads the
   bits. A `CARD64`'s halves are written from its bits already. A byte's
   or a word's value above its signed range (`#200` in a `MOVB`) is
   written in decimal as a `CHAR`'s is now, if MACRO takes it for the
   byte or word; the fixtures' assembly on the guest shows whether it
   does, and if not those are written in hexadecimal too.
8. **Every `FOR` loop ends before a step that would pass its final
   value**, signed or unsigned, as on LLVM (`ForStatement`). After the
   body, the distance left, `temp - v` counting up and `v - temp`
   counting down, at `v`'s width and so modulo 2^n, is compared unsigned
   with the step's size, and the loop ends when it is smaller; otherwise
   `v` is stepped and the head's test runs again (which matters only when
   the body moved `v` past `temp`). The head's test is unsigned for a CARD
   (proposal 2). A quadword's distance is a quadword subtraction and an
   unsigned `QuadRelation`. The loop leaves `v` at the last value the body
   had.
   - This changes the code of every `FOR`, so the expected MACRO-32 of the
     21 fixtures with one changes, and those of `rtl/vax`'s 10 modules
     with one in each fixture that sends them, all for review.
   - poc's own source has `FOR` loops, so the VAX-built poc changes too;
     `make vax-stages` is run again, to the fixed point.
9. **`rtl/vax` gains the runtime's `Card` procedures, from `rtl/llvm`
   unchanged.** They are plain Oberon over `HUGEINT`, which the VAX
   backend compiles already.
   - `CardinalTypes.Mod`, a copy of `rtl/llvm`'s.
   - `FormattedText.Card` and `CardHex`, `FormattedInput.Card`,
     `FormattedOutput.Card` and `CardHex`, `Out.Card` and `CardHex`,
     `Err.Card` and `CardHex` (over `CardinalTypes.Card64`), `In.Card`,
     each added to `rtl/vax`'s module, and the header comments' lists.
   - `InStr` and `OutStr` become copies of `rtl/llvm`'s again, so
     `vax-instr` and `vax-outstr` pass.
   - `PocRtl.mar` gains `POC_CDIV`, `POC_CMOD` and `POC_CTOG`, and
     `tools/vax-runtime-stub.mar` stand-ins for them (section 19.12's
     lesson: a new `PocRtl` entry needs one there).
   - `vax-library`'s `POCRTL` gains `CardinalTypes`.
10. **Fixtures, new, built under `-O2` and run on the guest, as the LLVM
    fixtures are.**
    - `vax-cardinal`: `llvm-cardinal`'s `cardinal.mod`, which must print
      `llvm-cardinal`'s `expected`. Nothing it prints depends on
      `SYSTEM.CARD`'s width or on IEEE: its reals are printed in
      decimal, and `MAX(SYSTEM.CARD64)` as a `LONGREAL` is
      1.8446744073709552E19 in G too. Its expected MACRO-32 is kept, for
      review, as the backend's fixtures keep theirs.
    - `vax-for-loop-end`: `llvm-for-loop-end`'s `forend.mod`, which must
      print that fixture's `expected`.
    - `vax-cardinal-traps`: `llvm-cardinal-traps`' four programs, each
      ending in its trap (2 for the indexes; 14 for `SHORT` and `CHR`,
      under `-range-checks`), with the status and message the VAX gives
      for each.

### 20.2 Unsigned integer types: done

- *Done* (section 20.1, proposals 1 to 10, 2026-10-14):
  - `VaxCodeGenerator` chooses by the operand's family wherever a CARD
    differs from a signed integer.
    - `Extension` gives `MOVZ` for a CARD and `CVT` otherwise, for
      `MoveInto`, `Widen` and `SYSTEM.VAL`.
    - `IsUnsigned` (a `CHAR` or a CARD) picks the unsigned branches for
      `FalseBranch`'s callers and `QuadRelation`.
    - `CardDivMod` divides as proposal 3 says.
    - `AsReal` converts a CARD, and its four callers now convert
      whenever the operand is a CARD, not only for a quadword.
    - `Lsh` became `LogicalShift`, which `Ash` of a CARD calls.
      `ShiftCount` takes a CARD count.
    - `Short`, `Chr` and `Abs` are as proposal 6 says.
    - `HalfText` writes a `CARD32` above 2^31 - 1 in hexadecimal.
    - The new `ForStatement` ends every loop as proposal 8 says.
    - An operand keeps its constant's `Types.Value`. A constant compared
      or combined with a CARD takes the CARD's type
      (`AdoptConstantType`, by `Types.ConstantOperandType`), so that
      200 against a `CARD8` is compared unsigned.
  - *One difference from proposal 6:* `SHORT` of a CARD still truncates
    by `CVT`, not by `MOVx` from the low end. For a value that has
    passed the check, the result is the same.
  - *Proposal 7's open point:* MACRO assembles a byte or word immediate
    above its signed range written in decimal (`MOVB #200`, `CMPB
    ..., #255`, `MOVW #65535`) to the same bits. So those stay in
    decimal, and only longwords and quadwords are written in
    hexadecimal.
  - `rtl/vax`:
    - `CardinalTypes.Mod` is `rtl/llvm`'s.
    - `FormattedText`, `FormattedInput` and `In` take `ff457c2`'s hunks.
    - `FormattedOutput`, `Out` and `Err` gain `Card` and `CardHex`, by
      hand; `Err`'s are over `CardinalTypes.Card64`.
    - `InStr` and `OutStr` are `rtl/llvm`'s again, plus the one line
      noting that they are copies.
    - `PocRtl.mar` gains `POC_CDIV` and `POC_CMOD`. They enter
      `HDIVMOD`'s loop past its sign handling and floor, with R10
      negative (`MNEGL #1`) marking the unsigned case. It also gains `POC_CTOG`.
    - `tools/vax-runtime-stub.mar` has the same three, with its `HDIV`
      to `ENTIERQ` block identical to `PocRtl`'s.
- *Fixtures.*
  - `vax-cardinal`, new: `llvm-cardinal`'s `cardinal.mod`, which prints
    `llvm-cardinal`'s `expected` on the guest.
    - The procedure sends `SYS$ERROR` to `CARDINAL-ERR.TXT` and types it
      after the run, as the run captures only `SYS$OUTPUT`.
    - `test.sh` makes `guest-run.expected` from `llvm-cardinal`'s
      `expected`, with the `Err` line moved below "-- SYS$ERROR".
  - `vax-for-loop-end`, new: `llvm-for-loop-end`'s `forend.mod`, which
    prints that fixture's `expected`.
  - `vax-cardinal-traps`, new: `llvm-cardinal-traps`' four programs under
    `-range-checks`.
    - Each prints "A" and traps: status `%X10000012` (2, "index out of
      range") for the two indexes, and `%X10000072` (14, "SHORT
      argument out of range" and "CHR argument out of range").
    - Making one expectation wrong failed the fixture, so the guest
      really runs it.
  - The reviewed expected MACRO-32 that changed, 40 files:
    - Proposal 8, the `FOR` loops' new end (five lines and one label a
      loop): the main modules of 13 fixtures, `vax-modules`' `VaxModLib`
      and `vax-type-bound`'s `VaxMethLib`, and `rtl/vax`'s `GarbageCollectedHeap`, `Modules`,
      `RealDigits`, `Platform`, `Files` and `FormattedText`, in each
      fixture that sends them.
    - Proposal 9, the new `Card` and `CardHex`: `Out`, `Err`,
      `FormattedOutput` and `FormattedText`, with their keys and line
      numbers. Also the main modules of `vax-out`, `vax-err` and
      `vax-modules-commands` and its `Greeter`, whose only change is the
      key of `Out` or `Err`.
  - `vax-err` compiles and compares `CardinalTypes`
    (`expected-vax-CardinalTypes.mar`, new). It and `vax-out-reals` send
    `CardinalTypes.mar` to the guest with `Err`'s other imports.
  - The debugger runs' reviewed transcripts (`run-*.log`) that changed:
    - `vax-for`'s three: each loop's variable keeps its last value (3, 2,
      99999 and 5 for n = 3). The breakpoints (`SET BREAK %LINE`) move to
      the listing's new lines 102, 119, 134 and 153, which count the
      header comment too.
    - `vax-index-registers`: the `FOR` leaves i at 1, so the `WHILE`
      does not step and `s[1]` becomes {0, 1}.
    - `vax-copy-long` and `vax-parameters`: "value returned" is R0 after
      a proper procedure, now the last loop's distance, 0, where it was
      a value left from before.
    - `vax-reals`: the divide fault's PC, label and listing line.
  - `vax-library`'s `POCRTL` has 26 modules and makes 560 symbols
    universal, 18 more.
  - `vax-instr` and `vax-outstr` pass again.
  - `VaxFor.mod`'s comment no longer says the loop is the report's
    equivalence. It is reworded within the same lines, so no line number
    moves.
- *poc on the VAX.* poc's own `FOR` loops changed, so `make vax-stages`
  was run again to the fixed point (V1 = V2 = V3).

## 21. Distributing poc on VAX/VMS (Phase 17 close-out)

poc runs on VAX/VMS (section 17: `make vax-stages` reaches V1 = V2 = V3)
and builds libraries there (section 18), but the only way a VMS system
gets a `POC.EXE` today is `vax-stages -install` on the development
system, and nothing puts poc for VMS into a release. The Unix side has
the seed (Phase 13 step 4): poc's own LLVM IR in the tarball's `seed/`,
from which clang alone builds poc. These proposals do the same for VMS,
from what already exists:

- `tools/bootstrap/vax-v1` writes poc's V1 stage on the host: 35 `.mar`
  files, 5.4 MB, with their `.sym` files and `Poc.com`, which assembles
  and links them into `POC.EXE` with `POCRTL.OBJ` from `POC$RTL`.
- `poc -target vax-dec-vms -library` writes a library's `.mar`, `.sym`,
  `.owner`, manifest, `<name>_build.com` and `<name>_setup.com`
  (section 18.5). `POCRTL`, `VMSDEF` and `VMSLIB` together are 829 files
  and 4.5 MB under each size model (measured 2026-10-15).
- poc on VMS finds its libraries in `[<parent>.LIB.POC]`, beside the
  `[.BIN]` its image is in (`Libraries.VmsLibraryDir`), then in the
  search list `POC$LIBRARY`; a library sits in
  `[.VAX-DEC-VMS.<O2|OC>]` below that.

Two facts shape what a kit can be. A file copied to VMS by FTP in binary
mode lands as fixed 512-byte records, so an image, an object or a
`BACKUP` saveset made elsewhere does not survive the crossing, while text
in ASCII mode does. And nothing on the host can write a `BACKUP`
saveset or a VMSINSTAL kit. All of the kit's file names were checked
against ODS-2's rules: a name and a type of at most 39 characters each,
of `A`-`Z`, `0`-`9`, `$`, `_` and `-` (*Guide to VMS Files and Devices*
5.0), and no two that differ only in case. A directory hierarchy is at
most nine levels deep, the master directory included (*VMS File System
Internals*, 2.4.3).

### 21.1 Proposals

**Approved by the user, 2026-10-15**, all nine as written. Proposal 10,
two kits, was asked for and approved by the user the same day; it
changes proposals 1, 2, 3, 4, 6 and 7 where they say "the kit".

1. **A VAX kit, all text, made on the host.** `make vax-kit`
   (`tools/bootstrap/make-vax-kit`) writes `build/vax-kit`. It runs on
   the host only and never uses the guest. The kit holds:
   - poc's V1 stage: the `.mar` files and `Poc.com`, with `PocRtl.mar`;
   - the libraries `POCRTL`, `VMSDEF` and `VMSLIB`, each written by
     `-library` under both `-O2` and `-OC`, as text only (no `.OLB` and
     no `.EXE`);
   - poc's source and `rtl/vax`'s, as much of them as poc for VMS is
     built from, so that poc can recompile itself there (proposal 7);
   - `README.TXT` and `LICENSE.TXT`.

   It holds nothing binary: `POC.EXE` and each library's `.OLB` and
   `.EXE` are made on VMS, by the base kit's MACRO, LINK and LIBRARY
   (proposal 3). That takes longer than copying an image, but it is the
   only way across that a plain FTP transfer allows. It also means a
   site can check what it runs against the release's source.

2. **One file: a DCL procedure that unpacks itself.** The kit is a
   single file, `POC-<version>.COM`, with the version's periods made
   hyphens (`POC-0-7-0.COM`). For each file it holds:

       $ CREATE [.LIB.POC.VAX-DEC-VMS.O2]LIBDEF.MAR
       $ DECK/DOLLARS="<marker>"
       ...the file's lines...
       <marker>

   `DECK` lets a data line begin with `$` (*DCL Dictionary* 5.4,
   DCL1-111). `make-vax-kit` picks a marker no line of the kit begins
   with, and checks that it did. The file is about 15 MB, and it is
   carried by one ASCII FTP transfer (or any text transfer), and run
   with `@POC-0-7-0` in an empty directory, which becomes the top of the
   installation. That top gets:
   - `[.BIN]`, for `POC.EXE`;
   - `[.KIT]`, V1's `.mar` files, which can be deleted once `POC.EXE` is
     built;
   - `[.LIB.POC.VAX-DEC-VMS.O2]` and `[.OC]`;
   - `[.SRC]`, holding `[.FRONT]`, `[.BACK.VAX]`, `[.DRIVER]`,
     `[.DRIVER.NO-LLVM]`, `[.RTL]` and `[.RTL.VMS]`, without the LLVM
     back end (proposal 8);
   - `BUILD.COM`, `SETUP.COM`, `README.TXT` and `LICENSE.TXT`.

   The deepest of these, `[.LIB.POC.VAX-DEC-VMS.O2]`, is four names
   below the top, so the top may be four names deep at most
   (`DUA1:[USERS.POC.TOOLS.POC]`).

   The rejected ways:
   - one ASCII transfer per file: 1,700 files in nine directories;
   - a `BACKUP` saveset or a VMSINSTAL kit: binary, and nothing on the
     host makes one.

   One thing must be tried on the guest before the rest is built: the
   longest line a `CREATE` in a procedure takes whole. No `.mar` line,
   V1's or a library's, is longer than 140 characters. The long lines
   are in `VMSDEF`'s `.sym` files, where `ModuleInterface` writes a
   record type on one line: 378 lines exceed 255 characters, and the
   longest, `ENSDEF`'s, has 973. If DCL takes less, `.sym` files break
   such a declaration over lines.

3. **`BUILD.COM` builds everything in place.** `@BUILD` does three
   things:
   - It assembles `[.KIT]`'s `.mar` files and `PocRtl.mar` and runs
     `Poc.com` there, as `vax-stages` does, then moves `POC.EXE` to
     `[.BIN]`.
   - Under each size model it runs, in `[.LIB.POC.VAX-DEC-VMS.<model>]`,
     `POCRTL_SETUP` and `POCRTL_BUILD`, then `VMSDEF`'s, then `VMSLIB`'s.
   - It deletes the objects.

   P1 is `O2`, `OC` or `BOTH` (the default), so that a site that wants
   only one size model can halve the work. P2 `CLEAN` also deletes
   `[.KIT]`. Each step writes its time and status to `BUILD.LOG`, and
   the first failure stops the build with its status. It needs no
   privilege, and it needs nothing outside the base kit. `VMSDEF`
   already links from its `.OLB` within POC's quotas (section 18.5).

4. **`SETUP.COM` makes poc usable in a process.** `@SETUP` does two
   things:
   - It defines `POC :== $<device>[<top>.BIN]POC.EXE`.
   - It runs the three libraries' `_SETUP.COM` under one size model: P1
     is `O2` (the default, as `poc`'s) or `OC`.

   It is meant to be called from `LOGIN.COM`. poc then finds its
   libraries by itself, through `VmsLibraryDir`, so `POC$LIBRARY` is
   needed only for a site's own libraries elsewhere.

   The size model is a parameter because a library's setup names one
   directory in `POC$LIB_<NAME>`: a process can build against `-O2`'s
   libraries or `-OC`'s, not both at once. Changing models means running
   `@SETUP OC` again. This is a limit of section 18's design, written
   down here and left for later. Names per model, such as
   `POC$LIB_OC_POCRTL`, would lift it.

   A site-wide installation is not proposed:
   - `DEFINE/SYSTEM` needs `SYSNAM`;
   - `INSTALL` of the shareable images needs `CMKRNL`;
   - neither has been tried.

5. **The version is the release's.** `make-vax-kit` writes
   `BuildInfo.Mod` from the tree (`tools/build-info <dir> vax-dec-vms`),
   so the VMS poc's `-version` names the same version and commit as the
   tarball's poc. The kit's first lines are comments that give the
   version, the commit and how to install. As `make dist` does for the
   seed, the kit is refused from a tree with uncommitted changes when it
   goes into a release.

6. **Into the release.**
   - `make dist` runs `make-vax-kit` and puts the file in the tarball as
     `vax/POC-<version>.COM`.
   - The GitHub release also carries it as its own asset, since that one
     file is all a VMS site needs, and it goes into `SHA256SUMS` like the
     rest.
   - `doc/developer/DEVELOPER.md` section 7 gets the steps.

   None of this happens before `vax` is merged into `main`, which is the
   user's decision. Until then, `make vax-kit` works on `vax` alone.

7. **Checked on the guest.** `make check-vax-kit`
   (`tools/bootstrap/check-vax-kit`) runs the kit as a site would, in a
   scratch `[.KITCHECK]` under POC's home, with the guest's lock held:
   - it carries the one file to the guest by ASCII FTP;
   - it runs the file, then `@BUILD`, then `@SETUP`;
   - it runs `poc -version`;
   - it builds and runs `hello` under `-O2` and `-OC`, and a program that
     uses `VMSLIB` against the installed libraries;
   - at the end it deletes the scratch directory.

   With `-full`, it also recompiles `[.SRC]` with the kit's `POC.EXE`
   and compares the result with `[.KIT]`'s `.mar`: the fixed point,
   about 45 minutes more. This target, like `vax-stages`, is not part of
   `make check`. It runs at this phase's close and before each release
   with a kit.

8. **poc for VMS leaves the LLVM back end out.** This settles the open
   design question "poc on VAX/VMS carries the LLVM back end"
   (`PLAN.md`), and it is done before the kit is made, since it changes
   what goes into the kit.

   - *What it saves.* `LLVMCodeGenerator`, `LLVMToolchainDriver` and
     `LLVMTypes` are 1.48 MB of V1's 5.4 MB of `.mar`. `Poc.mar`'s share
     of LLVM work comes on top. Leaving them out cuts:
     - the time to assemble `POC.EXE` in `BUILD.COM`;
     - the time to compile in each `vax-stages` stage, since those
       modules have about 10,500 lines;
     - `POC.EXE`'s size.

     It also removes code that, on VMS, could only run untested: an LLVM
     `-target` writing `.ll` files from VMS, through a driver that
     assumes a Unix host.
   - *What ties them in today* (2026-10-15):
     - `Poc.Mod` names the LLVM modules in 106 places. 35 of those are
       `LLVMCodeGenerator.ModuleList`, the driver's own list of modules
       being compiled. The rest are the LLVM options, the host triple,
       clang, and `EmitIR`, `Build` and `BuildLibrary`.
     - `VaxCodeGenerator` imports `LLVMTypes` for the method slots:
       `MethodSlotCount`, `SlotMethod` and `SlotOfMethod`, which use only
       `Types`.
     - `VaxToolchainDriver` names `LLVMToolchainDriver` only in a
       comment.
   - *The shared pieces move out of the LLVM back end:*
     - `ModuleList`, `ModuleListDesc` and `SourcePath` move to a new
       front-end module, `ModuleLists`, which `LLVMCodeGenerator` and the
       driver both import.
     - The three method-slot procedures move to a new front-end module,
       `MethodSlots`, which both code generators import.
   - *Poc.Mod's LLVM work moves behind one module.* A new
     `LLVMBackEnd` in `src/driver/llvm` holds what `Poc.Mod` does only
     for an LLVM target. That means handling the LLVM options (`-lto`,
     `-opt`, `-emit-llvm-ir`, `-static`, `-link`, a C or C++ part, and so
     on), the host triple and clang's version, compiling, building, and
     making and installing a library. It also holds the LLVM half of
     `-help`. `Poc.Mod` then imports `LLVMBackEnd` and none of the three
     LLVM modules.
   - *A second `LLVMBackEnd` for VMS.* `src/driver/no-llvm/
     LLVMBackEnd.Mod` has the same exported interface, and each of its
     procedures refuses: "poc on VAX/VMS has no LLVM back end: -lto"
     (exit 2). Its `-help` half is empty, so poc on VMS lists only the
     options it takes. The import path decides which one a build gets:
     - Stage 1, Stage 2 and the seed use `src/driver/llvm`;
     - `vax-v1`, and so `vax-stages` and the kit, use
       `src/driver/no-llvm` and leave `src/back/llvm` off the path.

     A new fixture compiles both and compares their interfaces
     (`-show-interface`), so the two cannot drift apart unnoticed.
   - *Unchanged:* poc on Unix, every `.ll`, the Stage 1/Stage 2 fixed
     point, and V1 = V2 = V3. Each build is consistent with itself. V1's
     `.mar` changes once, by the modules that leave it, and `make
     vax-stages` is run again to the fixed point.
   - The decision goes into `doc/developer/design-decisions.md`, and
     `PLAN.md`'s question moves to "Decided".

9. **Documentation.**
   - The User's Guide gets a section "poc on VAX/VMS": getting and
     running the kit, `BUILD.COM` and `SETUP.COM`, the size models, the
     libraries, and `-build`'s procedures.
   - `README.TXT` in the kit is that section as text.
   - `INSTALL.md` points to it.
   - This section gets a "21.2 Done".

10. **Two kits: poc, and the STARLET part.** Much of one kit is
    `VMSDEF`, the 243 modules `tools/sdloberon` generates from
    `STARLETSD.TLB`, each assembled on VMS under both size models. With
    `VMSLIB` it is 3.9 MB of the 11.4 MB and 1,739 of the 2,005 files
    (measured 2026-10-15). poc needs none of it, nor does `POCRTL`. So
    the release carries two files, made by `make vax-kit` together:
    - `POC-<version>.COM`, the base kit: everything proposal 2 lists
      but `VMSDEF` and `VMSLIB`, their sources included, plus
      `VERSION.TXT`, one line naming the version and commit.
    - `POC-VMS-<version>.COM`, the STARLET kit: `VMSDEF` and `VMSLIB`
      (which imports `STARLET`, `LIB_ROUTINES` and `LNMDEF`) under both
      size models, `[.SRC.RTL.VMS]`, `[.SRC.RTL.VMSLIB]` and
      `README-VMS.TXT`.

    The STARLET kit is run in the top of a base installation, at once
    or later, and refuses unless `VERSION.TXT` is there and names its
    own version and commit (a library from another poc is refused by
    poc anyway), or if it has been unpacked there already. A library's
    files go to the kit of the library its `.owner` names.

    `BUILD.COM` builds what is not built yet: `POC.EXE` unless `[.BIN]`
    has one, and each library whose build procedure is there and whose
    `.OLB` is not. So `@BUILD` after unpacking the STARLET kit builds
    only `VMSDEF` and `VMSLIB`; deleting a product makes the next
    `@BUILD` make it again. `SETUP.COM` runs the setup procedure of
    every library that is built, `POCRTL`'s at least.

    `make check-vax-kit` installs the base kit and builds and runs
    `hello` with it alone, checks that the STARLET kit refuses an empty
    directory, then unpacks the STARLET kit over the base and goes on
    as proposal 7 says, `@BUILD` building only the two libraries. Both
    files go into the tarball's `vax/`, into the release and into
    `SHA256SUMS`.

The exit gate (step 8) gains one condition: the kits build and pass
`make check-vax-kit` on the guest.

### 21.2 Distributing poc on VAX/VMS: done

- *Proposal 8, no LLVM back end on VMS* (2026-10-15):
  - `src/front/ModuleLists.Mod` holds `SourcePath`, `ModuleList` and
    `ModuleListDesc`; `LLVMCodeGenerator` keeps `SourcePath*` as an
    alias. `src/front/MethodSlots.Mod` holds `MethodSlotCount`,
    `SlotMethod`, `MethodSlot` and `SlotOfMethod`; `VaxCodeGenerator`
    imports it, not `LLVMTypes`, and `LLVMTypes` no longer imports
    `SyntaxTree`.
  - `src/driver/llvm/LLVMBackEnd.Mod` is the facade: the LLVM options'
    setters, the host triple and clang's version, `CheckLTOTarget`
    (moved from `Poc.Mod`), the LLVM part of preparing libraries, and
    `EmitIR`, `Compile`, `Build` and `BuildLibrary`.
    `src/driver/no-llvm/LLVMBackEnd.Mod` has the same interface;
    `Available` is FALSE there. `Poc.Mod` imports neither LLVM module.
  - *One difference from the proposal:* the refusal is made once, by
    `Poc.Mod` (`IsLLVMOption`), as the arguments are read, not by each
    stub procedure: "poc: -lto is not available on VAX/VMS, where poc
    has no LLVM back end", and poc exits 1, as for any other bad
    argument (`%X1000000A` on VMS), not 2. `-help` leaves those options'
    lines out (`LLVMHelpLine`).
  - The build scripts: Stage 0, Stage 1, Stage 2, `stage0-poc` and the
    seed put `src/driver/llvm` on the import path; `vax-v1` and
    `vax-stages` put `src/driver/no-llvm` there and leave
    `src/back/llvm` off. `make check-strict` also checks
    `src/driver/no-llvm`.
  - V1's `.mar`: 5,524,118 bytes before, 4,065,979 after, still 35
    files.
  - Fixtures: `driver-llvm-back-end`, new, compiles both
    `LLVMBackEnd`s and compares their interfaces. `vax-poc`'s `-help`
    expectation leaves out the LLVM options, and it adds `-LTO
    -VERSION`, refused.
- *`.sym` lines broken for DCL* (proposal 2's open point, tried on the
  guest 2026-10-15): `CREATE` in a procedure took a line of 255
  characters and refused one of 973 ("-RMS-W-RTB, 973 byte record too
  large for user's buffer"); a line beginning with `$`, `$EOD` and tabs
  came through `DECK/DOLLARS` whole. `ModuleInterface` now holds a line
  in a buffer and breaks one longer than 250 characters after its last
  `;` or `,` (record fields, parameter lists, value lists, `IMPORT`),
  continuing it six spaces in; shorter lines are as before. A module
  with such a line gets a new key: `VMSDEF`'s, `Files` in `rtl/vax`, and
  eight of poc's own (`Libraries`, `NestedProcedures`, `Poc`,
  `PredeclaredProcedures`, `SemanticActions`, `SymbolTable`,
  `SyntaxTree`, `Types`), which changes V1's `.mar` where they are
  imported. Of the reviewed fixtures only `vax-files` names such a key:
  its two `.mar` files take `Files`' new one, and nothing else in them
  differs.
- *Proposals 1 to 7 and 10, the kits* (2026-10-15):
  - `tools/bootstrap/make-vax-kit` (`make vax-kit`) writes
    `POC-<version>.COM`, 266 files and 7.5 MB, and `POC-VMS-<version>.COM`,
    1,739 files and 3.9 MB, in about 40 s; the longest line is 250
    characters. Each library file goes to the kit its manifest puts it
    in, and every file must go to exactly one.
  - `tools/bootstrap/vax-kit/` holds `BUILD.COM`, `SETUP.COM`,
    `README.TXT`, `README-VMS.TXT` and `check/`'s two programs.
  - `vax-v1` writes `Poc.com`'s first line with `src/driver/Poc.Mod`,
    not the host's path to it, since the kit carries it elsewhere.
  - `tools/bootstrap/check-vax-kit [-full]` (`make check-vax-kit`) as
    proposals 7 and 10 say.
  - `make dist` puts both kits in the tarball's `vax/` and beside it, and
    `tools/release-files` takes both.
  - Documents: the User's Guide, section 12, "poc on VAX/VMS";
    `INSTALL.md`, section 6; `DEVELOPER.md`, section 7's steps 3, 4 and
    6; `tools/bootstrap/README.md`.
- *What the guest found*, each fixed:
  - The base kit made no `[.BIN]`, the directory being empty on the
    host, so `RENAME` of `POC.EXE` into it failed. The kit now makes
    it, and `BUILD.COM` makes it when it is missing.
  - `$STATUS` is a string (`"%X00000001"`), so `F$FAO("!XL", ...)` of it
    printed an address (*DCL Dictionary* 5.4, DCL1-299: an argument of
    the wrong type gives "unpredictable results"). Every status is taken
    through `F$INTEGER`.
  - `BUILD.COM`'s symbol `LIBRARY` was seen by the library build
    procedures it runs, so their `LIBRARY/CREATE` became `POCRTL/CREATE`
    (`%DCL-W-IVVERB`). It is `LIBRARY_NAME` now, and `BUILD.COM` says
    why.
- *Measured on the guest*, 2026-10-15: `make check-vax-kit` passed.
  `@BUILD` of the base kit took 52 s (`POC.EXE` 28 s, `POCRTL` 11 s and
  12 s); after the STARLET kit, 1 min 53 s (`VMSDEF` 56 s and 53 s,
  `VMSLIB` 2 s each), `POC.EXE` and `POCRTL` left as they were. So
  `VMSDEF` costs little time on the emulated MicroVAX 3900; the split
  saves its 1,739 files and 3.9 MB for a site that does not want them.
  `make vax-stages` reached V1 = V2 = V3 with the new V1, the no-LLVM
  build and the broken `.sym` lines, in 39 minutes. `make check-vax-kit`
  with `-full` passed in 27 minutes: the kit's poc, compiling `[.SRC]`
  with `README.TXT`'s arguments, wrote V1's `.mar` files.

## 22. Asynchronous system traps (Phase 17 step 6)

`PLAN.md`'s step 6 asks what VMS's asynchrony demands of poc: AST
routines written in Oberon, the collector interrupted by an AST, the
runtime's other state, how a program shares data with its ASTs safely,
and condition and exit handlers. It is to be designed before any of it
is written. This section is that design: what the manuals say, what poc
does today, and the proposals.

### 22.1 What the manuals say

Only 5.x manuals, read 2026-10-15. *Introduction to VMS 5.5 System
Services* (`AA-LA68B`), *VMS 5.5 System Services Reference Manual*
(`AA-LA69B`), *Introduction to VMS 5.4 System Routines* (`AA-LA66B`,
whose chapter 2 is the calling standard) and the *VMS 5.0 RTL Library
(LIB$) Manual* (`AA-LA76A`).

- *An AST routine is an ordinary procedure.* "The system calls the AST
  with a CALLG instruction; the routine must return using a RET
  instruction", and saves what it uses beyond R0 and R1 in its entry
  mask (`AA-LA68B`, 5-3). Its argument list has five longwords: the AST
  parameter, then the R0, R1, PC and PSL "saved when the process was
  interrupted by delivery of the AST" (5-4). The calling standard's
  type `ast_procedure` is an entry mask's address, as `procedure` is
  (`AA-LA66B`, A-2).
- *One at a time.* "Because ASTs are implicitly disabled when an AST
  service routine executes, one AST routine cannot be interrupted by
  another AST routine declared for the same access mode" (`AA-LA68B`,
  5-5). A user-mode AST is not delivered while the process runs in an
  inner mode, a system service included, nor while delivery is disabled
  by `$SETAST`, which returns `SS$_WASSET` or `SS$_WASCLR`
  (`AA-LA69B`, SYS-512). Undelivered ASTs wait, in order. Otherwise the
  start of an AST routine "is impossible" to know (`AA-LA68B`, 5-3).
  `$WAITFR` and `$HIBER` are interrupted by an AST and resumed after it
  (`AA-LA69B`, SYS-663, SYS-402).
- *Quota.* An AST counts against `ASTLM` from its request to its
  delivery; past it, the request fails with `SS$_EXQUOTA`, with no
  wait (`AA-LA68B`, 7-3; `AA-LA69B`, SYS-134, SYS-486, SYS-521).
- *What is safe at AST level.* `LIB$GET_VM` and `LIB$FREE_VM` "are fully
  reentrant, so they can be called by code running at AST level"
  (`AA-LA76A`, LIB-224, LIB-178), and so are the queue routines
  `LIB$INSQHI` and the rest (LIB-249). `LIB$GET_INPUT` and
  `LIB$PUT_OUTPUT` keep RMS state in static storage and are not
  (LIB-213, LIB-311). Waiting at AST level for something only another
  AST of the same mode can bring is a deadlock (LIB-465). The manuals
  held say nothing of RMS at AST level.
- *Sharing data.* The manuals offer disabling ASTs around a sequence
  "that should not be interrupted" (`AA-LA68B`, 5-5), the interlocked
  queues, and `LIB$AST_IN_PROG`, for code that keeps separate storage
  for AST level (`AA-LA76A`, LIB-15).
- *Event flags.* Flags 0-31 and 32-63 are the process's own; 24-31 are
  VMS's. `LIB$GET_EF` hands out 32-63 at first, and 1-23 only once
  freed; flag 0 is every service's default, so two users of it collide
  (`AA-LA76A`, LIB-206; `AA-LA68B`, 2-11). A wait is for the flag, not
  the event, so an asynchronous service is finished by `$SYNCH` with its
  flag and I/O status block, which is what the `W` forms do (`AA-LA68B`,
  2-11, 7-15).
- *Condition handlers.* A handler's address in a frame's first
  longword, 0(FP), establishes it, as `LIB$ESTABLISH` does for its
  caller (`AA-LA66B`, 2-46). VMS calls it with the signal and mechanism
  arrays (2-49); it returns `SS$_CONTINUE` or `SS$_RESIGNAL`, or calls
  `$UNWIND`. A handler may use only its arguments, not the establishing
  procedure's locals (`AA-LA66B`, 2-51). The search goes through the
  current mode's frames by the saved FP (`AA-LA68B`, 11-6); whether it
  passes from an AST routine into the interrupted frames is not said.
- *Exit handlers.* `$DCLEXH` takes a control block: a link, the
  handler's address, an argument count, the address of a longword VMS
  fills with the exit status, and further arguments (`AA-LA69B`,
  SYS-137). They run, last declared first, from `$EXIT`, a return from
  the image, `$FORCEX` and an exit after an unhandled condition, "not a
  part of image rundown" (`AA-LA68B`, 8-13 to 8-15). Whether ASTs are
  delivered while they run is not said.

- *CTRL/C and mailbox attention.* `IO$_SETMODE!IO$M_CTRLCAST` on a
  terminal channel takes the AST routine in P1 (0 disables it), its
  parameter in P2 and the access mode in P3. It is "one-time": "After
  the AST occurs, it must be explicitly reenabled". All the enabled
  CTRL/C ASTs are delivered; `$CANCEL` flushes them; a program "should
  not enable CTRL/Y" (*VMS I/O User's Reference Manual: Part I*,
  `AA-LA84B`, 5.4, the 5.5 kit's edition, 8-42 to 8-43). A mailbox's
  `IO$M_READATTN` and `IO$M_WRTATTN` take the same P1 and P2, are also
  one-time, and a write attention AST requested while a message waits is
  delivered at once (7-9).

Not settled by the manuals held: the handler search from an AST, ASTs
during exit and condition handlers, whether `$CANTIM` withdraws a queued
AST, and RMS at AST level.

### 22.2 What poc does today

- *One calling convention, the standard's* (section 7, decided for
  Phase 15 so that "Phase 17's ASTs need nothing special"). An Oberon
  procedure with no hidden arguments - none of a `VAR` record's tag, an
  open array's lengths or a nested procedure's environment - is already
  a procedure VMS can call, and a procedure value is its entry mask's
  address. So `PLAN.md`'s choice between one convention and an adapter
  is already made: no adapter is needed. `CheckVmsCallbackType`
  (`SemanticActions.Mod`) admits exactly such procedure types.
- *The collector is not reentrant.* `Allocate` takes from per-size free
  lists and a bump pointer; `Collect` marks and sweeps through the same
  lists, the chunk table and a mark stack, all plain globals
  (`GarbageCollectedHeap.Mod`). An AST that allocates while the main
  line is inside `Allocate` or a collection corrupts them. A collection
  inside an AST would find every root: it scans the stack conservatively
  from its own frame up to the main program's FP, which covers the AST
  routine's frames, VMS's argument list holding the interrupted R0 and
  R1, and the interrupted frames, and `POC_SAVE_REGISTERS` saves R2-R11
  first. But it would run finalizers at AST level.
- *The rest of the runtime is not reentrant either.* Out and Err build
  lines in `LineOutput`'s two buffers; `In`, `Files`, `Texts` and
  `Platform` keep scratch state; a trap writes through `PocRtl`'s one
  buffer and then exits.
- *No handlers.* No poc frame establishes a condition handler; traps
  exit through `$EXIT`, not `LIB$SIGNAL`. `Platform.SetInterruptHandler`
  keeps its handler and never calls it ("Phase 17 step 6 decides").
- *Declarations.* `STARLET` declares every AST routine parameter
  `SYSTEM.ADDRESS`, with a comment `AST_PROCEDURE` (139 of them: 134 in
  `STARLET`, 4 in `SMG_ROUTINES`, 1 in `PPL_ROUTINES`), and the AST parameter `SYSTEM.CARD32`. Today a program
  passes `SYSTEM.VAL(SYSTEM.ADDRESS, P)`; `SYSTEM.ADR(P)` is an error
  ("SYSTEM.ADR requires a variable"), so `vms-sdl-interfaces.md`'s
  "`SYSTEM.ADR(P)` gives its address now" is wrong.
- *No interlocked instructions.* SYSTEM has none; `LIB$INSQHI`,
  `LIB$BBSSI` and the rest are declared in `LIB_ROUTINES`.

### 22.3 Proposals

**Approved by the user, 2026-10-15**, all nine as written.

1. **An AST routine is an Oberon procedure of one type.** A new module
   in `rtl/vax`, part of `POCRTL`, `AsynchronousTraps`, declares

       Routine* = PROCEDURE (parameter: SYSTEM.CARD32);

   and `tools/sdloberon` declares every parameter SDL types
   `AST_PROCEDURE` as `AsynchronousTraps.Routine` - and `LIB$SPAWN`'s
   `AST_address`, which SDL types only `procedure`, by its list of known
   exceptions - so that
   `STARLET.SYS$SETIMR(0, time, Tick, 7, 0)` is checked. `NIL` still
   omits it. A routine declares only the AST parameter; the four saved
   longwords after it are VMS's and are not read. No adapter and no new
   procedure kind: any global procedure of that type is an AST routine.
   Other routine parameters (`procedure`, `user_arg`) stay
   `SYSTEM.ADDRESS` until a module needs them typed. The wrong sentence
   in `vms-sdl-interfaces.md` is corrected.

2. **The heap is made safe against ASTs by disabling them, in programs
   that can have them.** `Allocate`, `Collect` and `RegisterFinalizer`
   run with user-mode ASTs disabled (`$SETAST 0` on entry, and `$SETAST
   1` on exit only if it returned `SS$_WASSET`), so an AST never finds
   the heap half changed, and NEW at AST level is safe. The cost, two
   system service calls for each NEW, is paid only once
   `AsynchronousTraps` is initialized: its body sets a flag the heap
   tests. Every module that can request an AST imports it - `STARLET`,
   `SMG_ROUTINES`, `PPL_ROUTINES` and `LIB_ROUTINES`, the generated
   modules with an AST routine parameter, and the modules of proposal 5 - so a program that cannot have an AST
   (poc itself, any program without `VMSDEF`) pays one byte test per
   NEW. The cost of the pair is measured on the guest before this is
   settled; if it is too high, the alternative is a flag the main line
   sets on entering the heap, which an AST's NEW tests, but then NEW
   at AST level can fail, and that is worse.

   A collection that runs at AST level (an AST's NEW, or `Collect`)
   does not run finalizers: they wait for the next collection on the
   main line, or for exit. `AsynchronousTraps.InProgress`
   (`LIB$AST_IN_PROG`) tells which.

3. **What else an AST routine may do is a documented rule, not made
   safe.** At AST level a program may use NEW, its own module's
   variables, the VMS interfaces - system services and `LIB$` routines
   documented reentrant - and the modules of proposal 5. It may not use
   `Out`, `Err`, `In`, `Files`, `Texts` or `Oberon`, whose state the
   main line may be halfway through, and it must not wait for something
   only another AST can bring. poc does not check this; the Reference
   Guide and `AsynchronousTraps`' comments say it. A trap at AST level
   ends the program as anywhere, through `$EXIT` with its status, and a
   fixture shows it.

4. **The main line shares data with ASTs by disabling them.** Since a
   user-mode AST cannot be interrupted by the main line or by another
   user-mode AST, only the main line needs protecting:
   `AsynchronousTraps.Disable(): BOOLEAN` and `Restore(wasEnabled)`
   bracket its use of what an AST changes. That is the manuals' own
   way, and all a program on one processor needs. SYSTEM gains no
   interlocked instructions; `LIB_ROUTINES`' `LIB$INSQHI` and the rest
   remain for whoever wants them (an entry linked only through a
   self-relative queue is invisible to the collector, which the
   comments say).

5. **The `VMS` modules `PLAN.md` asks for, in `VMSLIB`.**
   - `AsynchronousTraps` (`POCRTL`, proposal 1): `Routine`, `Disable`,
     `Restore`, `InProgress`, and `Declare(routine, parameter)` by
     `$DCLAST`.
   - `EventFlags`: `Get`, `Free` (`LIB$GET_EF`, `LIB$FREE_EF`), `Set`,
     `Clear`, `IsSet`, `Wait` and `WaitAny` of a local flag.
   - `Timers`: `After(milliseconds, routine, parameter, VAR request)` by
     `$SETIMR` with a delta time, `Cancel(request)` by `$CANTIM`, and
     `Sleep(milliseconds)` by `$SCHDWK` and `$HIBER`.
   - `Conditions` gains `Handler* = PROCEDURE (VAR signal:
     SignalArray; VAR mechanism: MechanismArray): SYSTEM.INT32`, with
     the two arrays as records of longwords, and `Establish` and
     `Revert`, declared as `LIB$ESTABLISH` and `LIB$REVERT` themselves so
     that the call comes straight from the procedure whose frame gets
     the handler, plus `Unwind` (`$UNWIND`). A handler is a global
     procedure, so it cannot touch its establisher's locals, which is the
     standard's own rule.
   - `ExitHandlers`: `Declare(handler)`, `handler` a `PROCEDURE (VAR
     status: SYSTEM.CARD32)`, VMS passing the exit status's address
     (`AA-LA69B`, SYS-137), each by its own
     `$DCLEXH` block kept by the module, so reachable. They run before
     poc's own (last declared, first run), so Out's last line is still
     flushed after them.
   - `$QIO` with a completion AST, and mailboxes, need nothing more than
     `STARLET` with proposal 1 and `VmsArguments`' I/O status block;
     a fixture shows them.

6. **CTRL/C by the terminal driver's AST.** `Platform.SetInterruptHandler`
   (now kept and never called) assigns a channel to `SYS$COMMAND` and
   enables `IO$_SETMODE!IO$M_CTRLCAST` with an AST routine in
   `Platform` that calls the handler and enables the AST again, it being
   one-time (`AA-LA84B`, 8-43). The handler runs at AST level, so
   proposal 3's rule applies to it. Not CTRL/Y, which the manual says a
   program should leave to DCL. With no terminal (a batch job) the
   handler is kept and never called, as now. A fixture cannot press
   CTRL/C, so it is tried by hand in the guest's telnet session.

7. **Tried on the guest first.** Before the rest is built:
   - `$SETAST` inside an AST routine: that disabling and re-enabling
     there does not let a second AST in (proposal 2's bracket runs at
     AST level too).
   - The cost of a `$SETAST` pair, against the time of a NEW, and so
     what proposal 2 costs a program that allocates much.
   - Whether a condition handler established in the interrupted code is
     found from an AST routine (decides what proposal 5's `Conditions`
     says).
   - Whether ASTs are delivered during an exit handler.

8. **Fixtures on the guest.**
   - `vax-asts`: `$DCLAST` and `Timers.After` deliver the parameter
     given; a timer that expires while `Disable` holds is not delivered
     until `Restore`, and then before the next statement; `$QIOW` from
     an AST; a mailbox read completed by an AST; a trap at AST level.
     It fails if any delivery rule above is wrong.
   - `vax-asts-heap`: a timer AST every 10 ms that builds lists with NEW
     and hangs them on a global list, while the main line allocates and
     collects for several seconds and checks every list's contents each
     pass; run several times (the gate's "repeatedly"). Made with the
     heap's protection off on purpose, it must fail, at least once in
     its runs, or it proves nothing; that is tried and recorded.
   - `vax-conditions-handlers`: a handler that continues, one that
     resignals, `Unwind`, an exit handler's status.
   - `vax-vmsdef` and `vax-vms-calls` take the typed `ASTADR`.

9. **What does not change.** The LLVM back end and every Unix program;
   poc's own speed (it imports no `VMSDEF`); the calling convention;
   the collector's algorithm.

### 22.4 Tried on the guest (proposal 7)

Four programs, run on the guest 2026-10-15 (built by poc, with their own
`["VMS"]` declarations; not fixtures):

- *Delivery.* The main line recorded 1, queued AST A by `$DCLAST`, and
  recorded 2; A recorded 101, queued B, called `$SETAST 0` and `$SETAST
  1`, and recorded 151; B recorded 200 plus its parameter. Then the main
  line disabled ASTs, queued B with 3, recorded 3 and 4, enabled them,
  and recorded 5. The order was 1 101 151 202 2 3 4 203 5: an AST
  queued by `$DCLAST` is delivered as the service returns, before the
  next statement; one queued inside an AST waits for it to return,
  though that AST disabled and enabled delivery; one held by `$SETAST 0`
  on the main line is delivered by `$SETAST 1`, before the next
  statement. `$SETAST 0` returned `SS$_WASSET` inside the AST as on the
  main line. So proposal 2's bracket is safe at AST level too.
- *Cost.* 20,000 `$SETAST` pairs took 120 ms, 6 us each, on the
  emulated MicroVAX 3900; 20,000 NEWs of an 8-byte record, 660 ms, the
  first chunk's clearing among them; 20,000 NEWs each in a pair, 430
  ms, after it. So the bracket adds about a quarter to a NEW, in the
  programs proposal 2 gives it to; that is accepted.
- *Handler search.* A handler established by the procedure an AST
  interrupted caught a warning the AST routine signalled by
  `LIB$SIGNAL`, both for an AST queued by `$DCLAST` (at depth 2) and for
  a timer AST that came during a busy loop (depth 1): the search goes
  on from the AST routine into the interrupted frames. So a handler the
  main line established can be called for a condition at AST level, and
  one that unwinds would leave the AST unfinished and the main line's
  frames gone. `Conditions`' comments (proposal 5) say a handler must
  not unwind for a condition signalled at AST level
  (`AsynchronousTraps.InProgress` tells).
- *Exit handlers.* An exit handler that queued an AST by `$DCLAST` got
  it delivered at once: ASTs are delivered while exit handlers run. So
  `GarbageCollectedHeap.FinalizeAtExit`, run by poc's exit handler, is
  within proposal 2's bracket like the rest of the heap.

### 22.5 The heap's protection, tried (proposals 2 and 8)

`vax-asts-heap`'s program, a timer AST every 10 ms making batches of 16
nodes with NEW while the main line makes lists of 500 and collects, was
run on the guest 2026-10-15 in three forms, from the same source but
for the lines that differ:

- With the heap's protection (it imports `AsynchronousTraps`): five runs,
  each checking 200 batches and their every node, with five or more
  collections, all intact.
- Without it (its own `Routine` type and `$SETAST`, no
  `AsynchronousTraps`): five runs, each ended by `%SYSTEM-F-ACCVIO` at
  virtual address 22 (hexadecimal) in the main program, at the same
  instruction each time, the emulator being deterministic.
- Without it, but with the main line's own NEWs bracketed by `$SETAST`
  by hand: three runs, all intact.

So the failure is an AST's NEW coming while the main line is inside the
heap, and the protection prevents it; the fixture fails without it.

### 22.6 As built

The proposals were carried out as approved, with these differences and
findings, each tried on the guest 2026-10-15:

- **The modules.** `AsynchronousTraps` is in `POCRTL`. `EventFlags`,
  `ExitHandlers` and `Timers` are new in `VMSLIB`, which `Conditions`
  joins with handlers. `tools/sdloberon` types every `AST_PROCEDURE`
  parameter, and `LIB$SPAWN`'s `AST_address`, as
  `AsynchronousTraps.Routine`: 134 in `STARLET`, 4 in `SMG_ROUTINES`, 1
  each in `LIB_ROUTINES` and `PPL_ROUTINES`. They were regenerated on atla
  by `sdlload` over SDL dumps, and differ from the old ones in those
  parameters and the `IMPORT` lines alone. `Timers` declares its own
  `$SETIMR`, and `Platform` its own `$ASSIGN` and `$QIOW`.
- **A handler's arrays are fixed arrays, not records.**
  `Conditions.SignalArray` is `ARRAY 256 OF SYSTEM.INT32` and
  `MechanismArray` is `ARRAY 5 OF SYSTEM.INT32`. An Oberon procedure's
  `VAR` record parameter takes the actual's type tag as a hidden second
  longword (section 14, item 5). VMS calls a handler with two addresses
  and no tags, so a record would put the mechanism array's address where
  the procedure looks for the signal array's tag. A `VAR` fixed array is
  one address.
- **`Timers.After(milliseconds, routine, parameter)` has no request
  argument.** `$SETIMR`'s request identification is the AST parameter
  itself, so `Cancel(parameter)` cancels every request made with it.
  `After` and `Sleep` take at least 10 ms, the clock's resolution.
- **Unwinding.** `Conditions.Unwind` is `$UNWIND` with its defaults. The
  establisher returns to its caller with `mechanism[3]` as its result.
  Every frame removed, the establisher's own included, has its handler
  called first with `SS$_UNWIND` (`Conditions.Unwinding`), so a handler
  that unwinds is called again: `vax-conditions-handlers` shows the
  order. An access violation is caught and unwound the same way.
- **Exit handlers.** Changing the status argument does nothing, since VMS
  writes the status into each handler's own longword. A handler that calls
  `$EXIT` ends the program there, with that status, which DCL sees. The
  handlers not yet called are skipped, poc's own among them, so Out's
  unfinished line is lost and no finalizer runs. `ExitHandlers` says so.
- **CTRL/C** (proposal 6), tried by hand by the user in a terminal
  session. A program that set a handler was given CTRL/C three times: the
  terminal driver echoed "Cancel" and the handler was called each time,
  with signal 2. After `SetInterruptHandler(NIL)`, which disables the AST,
  the next CTRL/C interrupted the program as CTRL/Y does ("Interrupt").
  `Platform` does not import `AsynchronousTraps` or the heap, so that
  every program using `Platform` neither links the heap nor pays for its
  protection (the user's choice, 2026-10-15). The rule instead: a handler
  that uses NEW needs the program to import `AsynchronousTraps`. A handler
  without NEW is safe either way, since the AST touches nothing of the
  heap's.
- **Fixtures.**
  - `vax-asts`: the delivery order, `Disable` and `Restore`, timers,
    `Cancel`, event flags, a mailbox read completed by a `$QIOW` from a
    timer's AST, and a trap at AST level, which ends the program with its
    message and status.
  - `vax-asts-heap`: section 22.5.
  - `vax-conditions-handlers`: the handlers and exit handlers above.
  - `vax-vmsdef` passes `NIL` for the AST routines it omits, and
    `vax-vmslib` compiles all six `VMSLIB` modules.

### 22.7 Proposal: a trap when the heap is re-entered

**Proposed 2026-10-15; approved by the user, 2026-10-15.**

The user chose (section 22.6) that `Platform` not import
`AsynchronousTraps`, so a program pays for the heap's protection only
when it imports that module itself. The rule that follows is: a CTRL/C
handler, or any AST routine, that uses NEW needs the program to import
`AsynchronousTraps`. Broken, the rule fails silently and by chance. An AST
that allocates while the main line is inside NEW or a collection corrupts
the heap. The program dies later, somewhere else: section 22.5's
unprotected runs ended by `ACCVIO` 5 of 5 times. The NEW may also be
hidden in a procedure the handler calls. This proposal makes that failure
immediate and named.

1. **A byte that says the heap is busy.** `rtl/vax/GarbageCollectedHeap`
   gains `inHeap: BOOLEAN`. `Allocate`, `Collect` and `RegisterFinalizer`
   test it after `EnterHeap`, set it, do their work, and clear it before
   `LeaveHeap`. Finalizers run outside it, as they run outside the `$SETAST`
   bracket now, so a finalizer's own NEW is not a re-entry. The inner
   `AllocateNow` and `CollectNow`, which call each other, do not touch it.
2. **Finding it set is a trap.** On VMS only an AST can interrupt the main
   line, so a public entry point that finds `inHeap` set has been entered
   by an AST that interrupted the heap. That is the one case that corrupts
   it. The program traps, as poc's other run-time checks do, before
   touching anything. The check has no window. An AST that comes between
   the main line's test and its setting of the byte, or after the byte is
   cleared, finds the heap untouched and not in use, and so does its work
   safely.
   - It is a new trap, **15**, with the text `heap re-entered at AST level:
     import AsynchronousTraps`, in `PocRtl.mar`'s `POC_TRAP_TEXTS`.
   - It is added to `language-extensions.md`'s table, "What traps, and what
     does not", as VAX only. Its location, under `-trap-location`, is
     inside the heap, so the message, not the location, tells the reader
     what to do.
3. **What it costs.** A `TSTB`, a `MOVB #1` and a `CLRB` per NEW, beside
   the 21-33 µs a NEW takes: nothing measurable. A program that imports
   `AsynchronousTraps` never finds the byte set, since ASTs are disabled
   while it is set, so the trap changes nothing for it.
4. **What it does not do.** It does not make NEW in a handler safe without
   the import. It reports the collision when it happens, and a program
   whose AST allocates when the main line is not in the heap still runs
   and is still wrong. The comments of `Platform` and `AsynchronousTraps`
   say both: the rule, and that breaking it ends in trap 15 at best.
5. **A fixture.** `vax-asts-heap` gains a second program,
   `AstNoImport.mod`, section 22.5's unprotected form: its own `Routine`
   type and `$SETIMR`, no `AsynchronousTraps`. Its AST allocates while the
   main line allocates and collects, and it must end in trap 15, with its
   message and status, not `ACCVIO` or a wrong list. It is run as often as
   the protected one. The emulator is deterministic, and the trial hit the
   same instruction every time, so the expected output is stable.
6. **The reviewed `.mar` files.** The heap's two copies, `vax-collector`'s
   and `vax-files`', are regenerated again for review. The heap's key does
   not change, since its interface does not, so no other reviewed file
   does.
7. **Not part of this.** The LLVM back end has the same hazard: a Unix
   signal handler, set by `Platform.SetInterruptHandler`, that allocates
   while the main line is in `GarbageCollectedHeap`. The same byte would
   catch it there, but the rule for signal handlers is a separate decision,
   left for `PLAN.md`'s "Ongoing" sections.

### 22.8 Interlocked queues and bits, tried (Phase 17 step 5)

Proposal 4 left `LIB$INSQHI` and the rest as `LIB_ROUTINES`' declarations.
`vms-sdl-interfaces.md`, part 10, proposal 4, wrote down the rules a
program follows to use them, and fixture `vax-interlocked` showed them on
the guest:
- **A header and every entry are quadword aligned** (`AA-LA76A`, LIB-248).
  poc aligns a global or a local to at most a longword
  (`MemoryLayout.Align`), but `NEW` gives quadword-aligned memory, since an
  object's data starts 8 bytes into a 16-byte granule. So a header and
  its entries are made by `NEW`: every address the fixture printed was 0
  modulo 8. A new header is zero, the empty queue.
- **An entry linked only through a queue is invisible to the collector**,
  since the links are displacements. A program keeps an ordinary pointer
  to each entry while it is queued. The fixture collects with four
  entries queued and removes them all intact.
- `LIB$REMQHI` and `LIB$REMQTI` give the entry's address, which
  `SYSTEM.VAL` makes the program's pointer type again. `LIB$_ONEENTQUE`
  on an insertion means the queue now holds one entry, and on a removal
  that it held one and is now empty. From an empty queue they return
  `LIB$_QUEWASEMP` and give **the header's own address**, not 0, so a
  program tests the status, not the address.
- `LIB$BBSSI` and `LIB$BBCCI` return the bit's old state, 0 or 1, and
  take any bit of a `SET` by `SYSTEM.ADR`.
- `LIB$ADAWI` returns `LIB$_NORMAL`, or `LIB$_INTOVF` when the word
  overflows (32767 + 1 leaves -32768), and its `sign` is the new sum's
  sign: 1 for 105, -1 for -95 and for -32768.

### 22.9 Subprocesses and ASTs (Phase 17 step 5)

`vms-sdl-interfaces.md`, part 11, proposal 4: two facts from the `LIB$`
manual (`AA-LA76A`) for a program that spawns.
- **A `LIB$SPAWN` that waits hibernates in supervisor mode** (LIB-386):
  `Subprocesses.Run`, and the routine without `CLI$M_NOWAIT`. A user-mode
  AST, a `Timers.After` among them, is not delivered until the
  subprocess ends and the call returns.
- **A completion AST** (`LIB$SPAWN`'s `AST_address`, with `NOWAIT`) runs
  at AST level under this section's rules, as any other; its status cell
  must still exist when VMS writes it, so it is a global, or a heap
  object the program keeps. Fixture `vax-subprocesses` uses one.

## 23. The command language routines, `CLI$` (Phase 17 step 5)

The inventory's item 5 (`doc/research/vms-native-library-inventory.md`)
leaves the `CLI$` routines to be declared by hand, since no SDL module
declares them. They let a program take DCL's qualifiers, parameters and
keywords as every VMS utility does, instead of splitting its line
itself, as `Modules` does. This section is the proposal for them. Its
sources are the VMS 5.0 *Command Definition Utility* manual (`AA-LA60A`,
"CDU" below) and the VMS 5.4 *Utility Routines* manual (`AA-LA67B`,
chapter CLI).

### 23.1 What the manuals say

- **Two ways to use them** (CDU, section 2.1). In the first, the
  program is run as a verb: a command definition file (`.CLD`) defines
  the verb with `IMAGE`, and `SET COMMAND` adds it to the process's
  command table. DCL then parses the line before the image runs, and
  the program asks about it with `CLI$PRESENT` and `CLI$GET_VALUE`. In
  the second, `SET COMMAND/OBJECT` makes an object module holding a
  command table, which is linked with the program. The program then acts
  as a command interpreter: it reads lines, parses each with
  `CLI$DCL_PARSE`, and runs the verb's routine with `CLI$DISPATCH`. A
  foreign command, CDU says, parses its own line: DCL does not.
- **`CLI$DCL_PARSE([command_string], table, [param_routine],
  [prompt_routine], [prompt_string])`.**
  - The command string is passed by descriptor and is at most 256
    characters.
  - The table is passed *by value*: the address of the global symbol
    that `SET COMMAND/OBJECT` defines, named by the `.CLD`'s `MODULE`
    statement, or else by its file name.
  - The two routines are called in `LIB$GET_INPUT`'s form, to ask for a
    missing parameter and for a line when the command string is left
    out. The prompt string is at most 32 characters.
  - It does no symbol substitution.
  - It both signals and returns an error. It returns `CLI$_NORMAL`,
    `CLI$_IVVERB`, `CLI$_NOCOMD` (an empty line), or `RMS$_EOF` (CTRL/Z
    at a prompt).
- **`CLI$DISPATCH([userarg])`** calls the routine that the `.CLD`'s
  `ROUTINE` clause names for the last verb parsed. It returns that
  routine's status, or `CLI$_INVROUT`. CDU says to give a `ROUTINE` for
  each verb of an object-module table. Its own example declares the table
  `EXTERNAL INTEGER TEST_TABLE`, and its routines are global names.
- **`CLI$GET_VALUE(entity, retdesc, [retlength])`** copies the next value
  of a parameter, qualifier or keyword path into `retdesc` by
  `STR$COPY_DX`, and gives its length in a word. It also knows `$VERB`
  (the verb's first four letters) and `$LINE` (the whole command). It
  returns `CLI$_COMMA` or `CLI$_CONCAT` when more values follow, and
  `SS$_NORMAL` for the last one. Absent, it returns `CLI$_ABSENT`. It
  signals when the entity is not in the table.
- **`CLI$PRESENT(entity)`** returns `CLI$_PRESENT`, `CLI$_NEGATED`,
  `CLI$_LOCPRES`, `CLI$_LOCNEG`, `CLI$_DEFAULTED` or `CLI$_ABSENT`.
- **A CLI must exist.** A detached process has none, and the manual
  says to check with `$GETJPI` first.
- A verb's and a qualifier's first four letters must be unique (CDU,
  `DEFINE VERB`), so `$VERB` tells the verbs of one table apart.
- The status codes are in the generated `CLIMSGDEF` (`rtl/vax/vms`).

### 23.2 What poc cannot do today (tried, 2026-10-15)

- **Name the table.** A `["VMS"]` declaration names only a procedure.
  poc has no way to take the address of an external *data* symbol, and
  `SYSTEM.ADR` takes only a variable.
- **Pass `LIB$GET_INPUT` as a routine.** "An external procedure cannot be
  used as a procedure value", for `["VMS"]` as for `["C"]`. An Oberon
  procedure in its place cannot be written either: VMS passes it a
  descriptor, and a procedure VMS calls "cannot have a VAR record or
  open-array parameter" (part 1, proposal 4). `PLAN.md`'s "Ongoing
  language enhancements", item 3, makes `SYSTEM.VAL(SYSTEM.ADDRESS,
  LIB$GET_INPUT)` the way.
- **Give a `ROUTINE` a name.** Every global symbol poc makes is a stem
  plus a hash (section 5), so a `.CLD` cannot name an Oberon procedure.
- **Link an extra object into a program.** `-build`'s options file lists
  the program's modules and libraries only (section 13), and `-link` is an
  LLVM option. (Since 2026-10-27 `-link` adds a line to the options file,
  section 13.)

### 23.3 Proposals

**Approved by the user, 2026-10-15**, all nine as written, then changed
three ways. Section 23.4 changes how proposal 1's `HasInterpreter` is done
and adds `ParseForeign`. Proposal 3 is replaced (the user, 2026-10-15) by
`PLAN.md`'s "Ongoing language enhancements", item 3:
`SYSTEM.VAL(SYSTEM.ADDRESS, E)` of an external procedure `E` gives its
address. That was made on `main` and merged into `vax`, so `ParsePrompting`
passes `SYSTEM.VAL(SYSTEM.ADDRESS, LIB$GET_INPUT)` for both routines, from
Oberon, as CDU's example does. Proposal 2 is replaced too (the user,
2026-10-15, after 23.4): the program passes its table's address, so
`CommandLanguage` has no MACRO-32 part at all. Section 23.5 has five more
changes, approved by the user the same day.

1. **A hand-written module, `CommandLanguage`, in `VMSLIB`**, beside
   `Conditions`, with a hand-written MACRO-32 part,
   `CommandLanguage.mar`, as a library's part is built (section 18). It
   declares the four routines as `["VMS"]` procedures and has typed
   procedures over them. The interface would look like this:

       PROCEDURE Present*(entity: ARRAY OF CHAR): SYSTEM.INT32;
         (* CLI$PRESENT's status, one of the constants below *)
       PROCEDURE IsPresent*(entity: ARRAY OF CHAR): BOOLEAN;
         (* present, present locally, or by default *)
       PROCEDURE GetValue*(entity: ARRAY OF CHAR;
                           VAR value: ARRAY OF CHAR): SYSTEM.INT32;
         (* the next value, 0X-terminated; Last, More, Concatenated
            or Absent *)
       PROCEDURE GetVerb*(VAR verb: ARRAY OF CHAR);   (* $VERB *)
       PROCEDURE GetLine*(VAR line: ARRAY OF CHAR);   (* $LINE *)
       PROCEDURE HasInterpreter*(): BOOLEAN;
         (* $GETJPI's JPI$_CLINAME is not empty *)
       PROCEDURE Parse*(line: ARRAY OF CHAR): SYSTEM.INT32;
       PROCEDURE ParsePrompting*(prompt: ARRAY OF CHAR): SYSTEM.INT32;
       PROCEDURE RestoreParse*(): SYSTEM.INT32;

   The status constants are renamed from `CLIMSGDEF`'s (`Present`,
   `Negated`, `Absent`, and so on). `GetValue` gives `STR$COPY_DX` the
   array as a `CLASS_S` descriptor and ends the value with 0X at the
   returned length. A value longer than the array is cut short, and it
   returns `Truncated` then, not one of `CLI$`'s codes. Errors that VMS
   signals stay signalled: `CLI$DCL_PARSE` prints DCL's own message for a
   bad line, as the CDU example relies on, and a misspelled entity stops
   the program with `CLI$`'s message, as it would in any other language.
   `Conditions` handles either, as usual. The name follows poc's naming
   (`AGENTS.md`); the module's comment says which `CLI$` routine each
   procedure is.

2. **The table is found by a weak reference to a fixed name.** In a
   program with a linked table, the `.CLD`'s `MODULE` statement must
   name the table `POC$COMMAND_TABLE`. `CommandLanguage.mar` refers to
   that symbol with `.WEAK`, so a program without a table links with no
   undefined-symbol warning and finds address 0. `Parse` and
   `ParsePrompting` take the address there. When it is 0 they return a
   status of their own, `NoTable`, without calling VMS. A program has at
   most one table, which is what CDU's examples show. Before anything
   depends on it, I will check that MACRO-32 and LINK in 5.5-2 handle
   `.WEAK` this way. That check uses the guest only, since I do not hold
   the 5.x MACRO-32 manual. If `.WEAK` fails, the fallback is a strong
   reference in a second object, `CommandTable.mar`, linked only when a
   table is.

   **Replaced: the program passes the table** (the user, 2026-10-15).
   Item 3 makes an external procedure's address something Oberon can take,
   and a table's global symbol can be declared as one:
   `PROCEDURE ["VMS", "SHELL_TABLE"] ShellTable;` for a `.CLD` whose
   `MODULE` statement is `SHELL_TABLE`. The procedure is never called; the
   program passes `SYSTEM.VAL(SYSTEM.ADDRESS, ShellTable)` to `Parse`,
   `ParsePrompting` and `ParseForeign`, which take it as their last
   argument. The weak reference was given up for three reasons:
   - **It fails in a shared VMSLIB.** A `.WEAK` reference is resolved when
     its own image is linked, so in `VMSLIB.EXE` (`-shared-libraries`) it
     would be 0 for good, whatever table the program links. Passing the
     address works whether VMSLIB comes from the `.OLB` or the shareable
     image.
   - **The name is the program's.** Any `MODULE` name works, not only
     `POC$COMMAND_TABLE`, and a program can have more than one table, a
     main one and one for a subcommand loop, say.
   - **No MACRO-32 part.** `CommandLanguage` is plain Oberon, built like
     the rest of VMSLIB.

   What it costs is one declaration in the program, whose comment says that
   the "procedure" is the table's data. A table address of 0, from a
   symbol LINK left undefined, gives `NoTable` (`CLI$_TABNOTFND`) without
   calling VMS, where `CLI$DCL_PARSE` would take an access violation.

3. **The prompting routines are `LIB$GET_INPUT`'s.** `ParsePrompting`
   passes `LIB$GET_INPUT` for both routines, plus the prompt.
   (Replaced; see above. As first proposed, a routine in
   `CommandLanguage.mar` passed `G^LIB$GET_INPUT`, since Oberon could not
   name an external's address.) `Parse` passes 0 for both routines, so a
   missing parameter is an error (`CLI$_INSFPRM`) and is not prompted
   for. A program that reads its lines itself, from a file for instance,
   wants exactly that. In a command procedure `SYS$INPUT` is the
   procedure, so data lines after the call answer `ParsePrompting`'s
   prompts, and `vax-cli-table` tests it that way (proposal 8).

4. **No `CLI$DISPATCH`: dispatch is done in Oberon on `$VERB`.** Since
   CDU makes a verb's first four letters unique, a program compares
   `GetVerb`'s result and calls its own procedure. This adds no names,
   no hash and no new linkage rule. A `.CLD` for poc then gives its verbs
   no `ROUTINE`. Whether `SET COMMAND/OBJECT` accepts a verb without one,
   and whether such a table parses, is a guest check (proposal 7). If CDU
   demands a `ROUTINE`, every verb names one never-called routine,
   `POC$NO_ROUTINE`, which `CommandLanguage.mar` defines, and the
   module's comment says so. `CLI$DISPATCH` is left undeclared, and the
   inventory says why.

5. **`poc -build` takes a `.cld` file.** On the command line of
   `-target vax-dec-vms -build`, a file ending `.cld`, in any case, is
   copied beside the `.mar` files. The procedure runs `SET
   COMMAND/OBJECT=<NAME>.OBJ <NAME>.CLD` before linking, and lists
   `<NAME>.OBJ` in `<IMAGE>.OPT` after the main module. At most one is
   allowed, since proposal 2 allows one table, and a second is an error.
   (Changed, section 23.5: any number, now that the program passes the
   table.)
   For an LLVM target, and with `-compile` or `-library`, a `.cld` is an
   error: "a command table is linked only by -build for vax-dec-vms".
   Leaving `-link` LLVM-only keeps section 21's split and needs no VMS
   options-file syntax on the host. `-help` and the User's Guide's chapter 12
   mention it. (Changed by the user, 2026-10-27: `-link` is a line of the
   options file for vax-dec-vms too, section 13.)

6. **A program run as a verb needs nothing more.** The `.CLD` defines
   the verb with `IMAGE`. The user, or the program's setup procedure, runs
   `SET COMMAND`, and the program calls `IsPresent` and `GetValue` only.
   The guest check is that `Modules`' body still starts cleanly when run
   that way: it calls `LIB$GET_FOREIGN`, and the manuals do not say what
   that returns for a CDU verb. Whatever it returns, `Modules.ArgCount`'s
   behaviour there is written into `CommandLanguage`'s comment.

7. **Checks on the guest before the module is written**, in a scratch
   directory under `POC`'s home, run with `tools/vax-do`. Each result is
   written into section 23.4 before any code depends on it.
   - `.WEAK` with and without the table linked (proposal 2).
   - `SET COMMAND/OBJECT` on a `.CLD` whose verbs have no `ROUTINE`, and
     whether `CLI$DCL_PARSE` then parses (proposal 4).
   - `LIB$GET_FOREIGN` in an image run as a CDU verb (proposal 6).
   - The inventory's open question: a program run as a foreign command,
     with `LIB$GET_FOREIGN`'s line given to `CLI$DCL_PARSE` and a linked
     table whose verb is the program's name. If that works, a foreign
     command can have DCL-style qualifiers without `SET COMMAND`, and the
     comment says how. If it does not, the comment says to use a verb.
   - What `CLI$PRESENT` returns in a process with no CLI, if one can be
     made unprivileged (a `RUN/DETACHED` of the image, `POC`'s quota
     permitting). If not, `HasInterpreter` is tested only for TRUE.

8. **Fixtures, on the guest**, each in the `vax-` family, run by `make
   check` when the guest is up, as the other `vax-` fixtures are.
   - `vax-cli-verb`: a `.CLD` defining a verb with `IMAGE`, one
     parameter with a list of values, a negatable qualifier with a
     value, a default qualifier, and a keyword. The procedure runs `SET
     COMMAND` and the verb several ways. The program prints what
     `Present`, `GetValue` and `GetLine` give, each `CLI$` status
     included.
   - `vax-cli-table`: a program built by `-build` with a `.cld`, reading
     command lines from a file and parsing each with `Parse`. It
     dispatches on `GetVerb` and prints each verb's qualifiers and
     parameters. Its lines include an unknown verb (signalled message,
     `IVVERB`), an empty line (`NOCOMD`), a missing parameter
     (`INSFPRM`), and a value longer than the array (`Truncated`).
     Last, `RestoreParse` brings back the invoking command's parse.
   - `vax-cli-table` also calls `ParsePrompting`, answered by data lines
     in its procedure: a whole line, then a line with its parameter
     missing, which the CLI prompts for. A `semantic-` fixture on the
     host checks the `.cld` errors of proposal 5.

9. **The documents.** This section's 23.4 (the guest's answers) and 23.5
   (as built). The inventory's item 5 is marked done, with what was left
   out and why: `CLI$DISPATCH`, and the prompting routines as Oberon
   procedure values. `rtl/vax/vmslib/README.md` lists the module.
   The User's Guide's chapter 12, "poc on VAX/VMS", gets a short example of a verb with a
   qualifier. `PLAN.md` step 5 gets a record of it all.

### 23.4 Tried on the guest (proposal 7, 2026-10-15)

Small MACRO-32 programs, run with `tools/vax-do` in `POC`'s directory.
Every `CLI$` call was made as `CommandLanguage` will make it.

- **`.WEAK` works as proposal 2 needs.** `.WEAK POC$COMMAND_TABLE`, with a
  longword `.ADDRESS POC$COMMAND_TABLE`, assembles, and links with no
  warning and the address 0 when no table is linked. With the table
  linked, the address is the table's, and `CLI$DCL_PARSE` parses with it.
- **A verb needs no `ROUTINE`** (proposal 4). `SET COMMAND/OBJECT` takes a
  `.CLD` whose verbs have none, with status `%X10118009`, a success.
  `CLI$DCL_PARSE` parses its lines: `SEND FOO.TXT,BAR.TXT/EDIT` gives
  `CLI$_NORMAL`, `CLI$PRESENT("EDIT")` gives `CLI$_PRESENT`, and
  `CLI$GET_VALUE` gives `FOO.TXT` with `CLI$_COMMA`, then `BAR.TXT` with
  `SS$_NORMAL`. `$VERB` gives `SEND`, and `$LINE` gives the line as given.
  `CLI$DISPATCH` signals and returns `CLI$_INVROUT`, so `POC$NO_ROUTINE`
  is not needed.
- **Errors are signalled, with a traceback.** An unknown verb prints
  `%CLI-W-IVVERB` and the verb, then `%TRACE-W-TRACEBACK` and the stack,
  and returns `CLI$_IVVERB`. An unknown qualifier does the same with
  `CLI$_IVQUAL`. The program goes on, since both are warnings. The
  traceback comes from linking with `/TRACEBACK`, LINK's default, which
  poc uses, and `Conditions.Signal` prints one too. A `CLI$PRESENT` or
  `CLI$GET_VALUE` of a name not in the table is fatal: `%CLI-F-SYNTAX`
  and `-CLI-E-ENTNF`, and the image stops. `CommandLanguage` leaves all of
  these as VMS does them, as proposal 1 says.
- **Run as a CDU verb, `Modules` works unchanged** (proposal 6). With
  `DEFINE VERB POCVERB IMAGE ...`, `POCVERB ALPHA/Q=BETA` gives
  `LIB$GET_FOREIGN` `ALPHA/Q=BETA` with `SS$_NORMAL`, the line after the
  verb as for a foreign command, so `Modules.ArgCount` is 2. `CLI$PRESENT`
  and `CLI$GET_VALUE` then answer from DCL's parse, with no table linked.
  A bare `POCVERB` gives an empty line, and `CLI$_ABSENT` for both.
- **A foreign command can parse its own line** (the inventory's open
  question). The image is run as `FOREIGN2 := $...FORT.EXE`, and a
  table is linked whose verb is `FORT`. `FORT `, followed by
  `LIB$GET_FOREIGN`'s line, is given to `CLI$DCL_PARSE`, and
  `CLI$PRESENT` and `CLI$GET_VALUE` then work as for a verb:
  - `FOREIGN2 ALPHA/Q=BETA` gives `BETA` and `ALPHA`;
  - `FOREIGN2 "lower case"/Q` gives `lower case`, with the quotes gone
    and the case kept;
  - `FOREIGN2 /BOGUS` gives `IVQUAL`, signalled.

  Before that parse, though, the process's parse is DCL's of the foreign
  command itself, so a question about the program's own qualifier is
  fatal (`ENTNF`). A foreign command must therefore parse first.
  `CommandLanguage` gets one more procedure for it,
  `ParseForeign*(verb: ARRAY OF CHAR): SYSTEM.INT32`, which parses
  `verb`, a blank, and `LIB$GET_FOREIGN`'s line with the linked table. A
  program can then be run either way, verb or foreign command, by
  calling `ParseForeign` only when `GetVerb` is not its own verb.
- **With no CLI**, in a process started by `RUN/DETACHED` (allowed to
  `POC`), every `CLI$` call returns `CLI$_INVREQTYP` (`%X00038822`). None
  signals or stops. `CLI$DCL_PARSE` does the same, even with a table
  linked. `LIB$GET_FOREIGN` gives `SS$_NORMAL` and an empty line. But
  `$GETJPI`'s `JPI$_CLINAME` is `DCL` there too, the UAF's CLI and not
  whether one is mapped, so it cannot answer `HasInterpreter`. Instead
  `HasInterpreter` asks `CLI$GET_VALUE("$LINE")`, which fails only when
  there is no CLI. The fixture runs one program detached, to show
  `HasInterpreter` FALSE and `Present` returning `InvalidRequest`, a new
  constant for `CLI$_INVREQTYP`.
- **A value's text after a failure is not to be read.** In the
  detached process, `CLI$GET_VALUE` returned an error but still copied
  the entity's own name into the value, with its length (`Q`, `P1`,
  `$LINE`). `GetValue` gives an empty value whenever the status is not a
  success.

### 23.5 As built (2026-10-15)

`rtl/vax/vmslib/CommandLanguage.Mod` is Oberon only. It imports
`LIB_ROUTINES`, `CLIMSGDEF`, `LIBDEF` and `RMSDEF`, and declares
`CLI$DCL_PARSE`, `CLI$PRESENT` and `CLI$GET_VALUE` privately, since the
generator has no `CLI$` routines. Its interface is proposal 1's, with
`ParseForeign` (23.4) and the table passed (proposal 2, replaced), and five
more changes, all approved by the user, 2026-10-15:

1. **`Presence`, not `Present`**, is `CLI$PRESENT`: `Present` is the
   constant for `CLI$_PRESENT`, and one name cannot be both.
2. **More constants**, so that a program can test the results by name:
   `Parsed` (`CLI$_NORMAL`), `UnknownVerb`, `UnknownQualifier`,
   `MissingParameter`, `NoCommand` and `EndOfInput` (`RMS$_EOF`), besides
   23.3's and `InvalidRequest` (23.4).
3. **`NoTable` only for a table address of 0**, as proposal 2, replaced,
   says.
4. **`Truncated` (`LIB$_STRTRU`, a success) replaces `More`,
   `Concatenated` or `Last`** for a value cut short, so a loop over a list
   runs until `Absent`, as the `CLI$` manual's own loops do.
5. **`-build` takes any number of `.cld` files** (proposal 5).

`RestoreParse` passes 0 for the table too: the manual says only that a
command string and a prompt routine of 0 restore the parse of the command
that ran the image, and on the guest a table of 0 does as well.

**`poc -build`** (`Poc.Mod`, `VaxToolchainDriver.WriteBuildProcedure`):
each `.cld` after the program's file, in any case, is copied beside the
`.mar` files, compiled by `SET COMMAND/OBJECT=<T>.OBJ <T>.CLD` after the
modules are assembled, and its object listed after theirs in
`<IMAGE>.OPT`. A table whose object would be a module's is refused (the
module's `.mar` names the same `.OBJ`), as is one whose name is not a VMS
file name or that is not there. A `.cld` given to any other command, or to
`-build` for an LLVM target, is "a command table (.cld) is linked only by
-build for vax-dec-vms". `-help`, poc(1), the Reference Guide and the
User's Guide's chapter 12 say so.

**Fixtures:**
- `vax-build-command-tables` (host only): the procedure for two tables,
  and the refusals.
- `vax-cli-verb` (guest): the verb `POCCLI` from `CliVerb.cld`, run three
  ways, then detached. `Presence` gives `LocallyPresent` and
  `LocallyNegated` for a positional qualifier after each value, `Defaulted`
  and `Negated` for a default qualifier; `GetValue` gives `More`,
  `Concatenated`, `Last`, `Absent`, `Truncated`, and a keyword path's value
  (`STYLE.FULL`). Detached, `HasInterpreter` is FALSE and both return
  `InvalidRequest`.
- `vax-cli-table` (guest): `CliTable` with `CliCommands.cld`, built by
  `-build`. Its own lines, a table of 0, `RestoreParse` (`RUN CLITABLE`),
  three lines read by `ParsePrompting`, one with its second parameter
  asked for and given by the next data line, then `EndOfInput`; and run as
  a foreign command, through `ParseForeign`, a quoted parameter keeping its
  case.
- `vax-vmslib` compiles `CommandLanguage` under `-O2` and `-OC`.

**Found on the guest:**
- **Under a verb, `Modules` sees DCL's copy of the line**: uppercased but
  for quoted text, with the quotes gone and no blank before a qualifier
  (`A.TXT/LOG`), so its arguments are not the words typed. The module's
  comment says so.
- **`$LINE` drops quotes too**: `POCCLI/MARK "Lower Case"` is
  `POCCLI/MARK Lower Case/...`.
- **A program's output and VMS's messages overwrite each other in a file
  named by `DEFINE/USER SYS$OUTPUT`**: the image opens it once for `Out`
  and once for the message, each with its own position. A file DCL opens
  (`@P/OUTPUT=`, a batch log) is shared. `vax-cli-table` runs its program
  from a small procedure with `/OUTPUT` for this, and leaves out the
  tracebacks, whose addresses change with the code.
- **The User's Guide's example** (chapter 12, "A command with
  qualifiers") was run there as written, with its image named by a
  logical name: `GREET/TIMES=3 world` prints `3 times: Hello, WORLD`.

`CLI$DISPATCH` is not declared (proposal 4), and the prompting routines are
`LIB$GET_INPUT`'s only, not Oberon procedures (`vms-sdl-interfaces.md`,
part 1, proposal 4).
