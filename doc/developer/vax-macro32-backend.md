# The VAX/VMS MACRO-32 backend (Phase 15) — design

Status: written before any code (2026-10-05) for `PLAN.md` Phase 15, and
kept as the record of its decisions; the phase was done on 2026-10-08
(`doc/history/phases/phase-15.md`). Each section says what the manuals
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
  Phase 16's, as is an open array.
- **Real types**, for Phase 16 (out of Phase 15's slice): `REAL` is
  F_floating; `LONGREAL` is D_floating or G_floating. VAX C chooses with a
  qualifier, `/G_FLOAT`, defaulting to D_floating (`/NOG_FLOAT`), and a
  program compiled with `/G_FLOAT` links against a different run-time
  library (VAX C, the `CC` command's `/G_FLOAT` qualifier). FORTRAN and
VAX's other compilers may have the same choice; not checked. So poc should offer the same choice as an
  option rather than fix one format; the default is Phase 16's to settle
  (`PLAN.md` Phase 16 step 3a), along with what replaces IEEE 754's
  infinities and NaNs, which VAX formats lack
  (`language-extensions.md`, "Overflow, division and reals").

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
   `..._VA2IG0SM`; rename one".
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
  constants, `POC_DATA` the module's variables, zero-initialised (`.BLKB`)
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
  an error until then.
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
  mechanism).
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
  tag as a second longword. A field reached through a parameter's
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
  slice.
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
    VMS sees are Phase 16's, as for `POC_TRAP` (§9). **Decided with the
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
    slice (`ASSERT`, until its trap is settled, `NEW`, `SIZE` of a
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
sign; the others come with their constructs.

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
  given in `POC_TRAP_CODE`, `_LINE`, `_COLUMN` and `_MODULE` and ends the
  program, `POC_HALT` its code in `POC_HALT_CODE`; `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and `POC_HMOD` compute what
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
- `VaxToolchainDriver.Mod` is a stub that writes the `.mar` and reports
  that assembling is not available (`PLAN.md` Phase 15). As for IR, the
  `.mar` of every module compiled from source is written, or none, when
  `VaxCodeGenerator` reports what it cannot lower yet.

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
