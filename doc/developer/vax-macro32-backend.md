# The VAX/VMS MACRO-32 backend (Phase 15) — design

Status (2026-10-05): **a draft, written before any code**, for `PLAN.md`
Phase 15. Each section says what the manuals fix (a fact, with its source)
and what poc chooses: **Decided** where the user has agreed (2026-10-05),
otherwise a proposal. The questions still open are in §11, and the proposed
order of work in §12.

## 1. What Phase 15 is

`PLAN.md` Phase 15: `VaxTypes.Mod`, `VaxCodeGenerator.Mod` and a stub
`VaxToolchainDriver.Mod`, emitting MACRO-32 for **exactly Phase 8's
vertical slice** - integer types `SHORTINT` to `HUGEINT`, `CHAR`, `BOOLEAN`
and `SET`; module-level and local `VAR`s; fixed arrays and base-less records
as values; ordinary (not type-bound, not nested) procedures; IF, CASE, WHILE,
REPEAT, FOR, LOOP/EXIT and RETURN; the predeclared procedures that need no
heap (`ABS`, `ODD`, `CHR`, `ORD`, `CAP`, `LEN`, `INC`, `DEC`, `COPY`,
`HALT`); runtime traps; external procedures; several modules and the
program's entry (`doc/history/phases/phase-08.md`, "Explicit non-goals" and
steps 5-12). Not `REAL`/`LONGREAL` (Phase 8 left them to Phase 9), pointers,
`NEW`, the collector, type-bound procedures, open arrays or nested
procedures: Phase 16 step 3 brings those.

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
  chooses the shortest form.
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
  `Ropes.Length`, `Ropes_init`.
- The symbol is `<stem>_<hash>`. The hash is a fixed-width code of the full
  name, case included - for example 40 bits of FNV-1a written as 8
  characters `0`-`9`, `A`-`V` - so `Foo` and `foo` differ. The stem is the
  full name uppercased, each character outside `A`-`Z`, `0`-`9`, `_` and
  `$` turned into `_`, cut to the 22 characters that leave room for
  `_` and the hash. `Ropes.Length` might become `ROPES_LENGTH_0K7Q3M2A`.
  The stem is only for a human reading a map or a traceback.
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

Proposal (2026-10-05), not yet agreed.

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
   import closure can always be computed from `.sym` files. The `.sym`
   records, for each exported object and each compiler-made global
   (`_init`, type descriptors, module keys), the symbol it was given, and
   the version of the name scheme. At link time poc (or a separate check
   for hand-built links) walks the main module's import closure and stops
   if two different full names have one symbol: "`A.X` and `B.Y` both
   give `..._VA2IG0SM`; rename one". A `.sym` from another scheme version
   is an error at import, not a link failure later.
3. **Within a module**, as §5 says: its own definitions and the imported
   names it references, checked by poc at compile time, with source
   positions.

Details this depends on:

- **Module-level symbols must never collide with each other.** If `A`'s
  and `B`'s `_init` symbols collide, `B` is never loaded and layer 1 fails
  silently. Module names are unique in a program anyway, so the `_init`
  symbol should be short and unhashed where the name allows, and the
  closure check treats a collision between module-level symbols as an
  error in every case.
- **Private objects are local symbols** (`label:`, not `label::`), so they
  never enter a link; what can collide across modules is only exports and
  compiler-made globals.
- The Librarian probably reports a module whose global symbol is already
  in the library (`LIBRARY/INSERT`, `DUPGLOBAL`) - **not yet checked** on
  the development system. It sees only one library, so a collision
  between two libraries, or a library and an `.obj`, still rests on
  layers 1 and 2.
- The LLVM targets do not shorten names, so nothing changes there but the
  `.sym` field.

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
  as on LLVM, and a flag "initialised".
- Each procedure is an `.ENTRY` (§7). The module body is the procedure
  `<Module>_init`, which returns at once if its flag is set, otherwise sets
  it, calls its imports' `_init`s in import order and runs the body.
- The **program's start** is one routine, written into the main module
  only, with `.END` naming it: it calls the main module's `_init` and
  returns `SS$_NORMAL` (1) in `R0`. `HALT(n)` and a trap end the program by
  a runtime routine (§9). How an exit status reaches DCL is Phase 16 step
  3c's to settle.
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
- **Results**: up to 32 bits in `R0`, `HUGEINT` in `R0`/`R1` (low, high);
  Oberon functions return no structured values.
- **Locals** live below `FP`, at negative offsets, allocated with one
  `SUBL2 #size, SP` and cleared, as LLVM's are.
- **Registers**: the body uses `R0`-`R5` as scratch for expression
  evaluation; `R6`-`R11` are kept for later (register variables, or
  Phase 16's needs). The entry mask saves those of `R2`-`R11` the body
  writes.
- **Overflow**: the `IV` bit stays clear, so integer arithmetic wraps, as
  poc promises (`language-extensions.md`, "Overflow, division and reals").
  An opt-in overflow check could later set it.
- **External `["VMS"]` procedures**: the linkage name verbatim (§5); a
  value parameter of 4 bytes or less by immediate value, a `VAR` parameter
  by reference. Descriptors and an explicit choice of mechanism per
  parameter are Phase 17 step 5's (`PLAN.md`); a parameter needing one is
  an error until then.
- **Nested procedures** are outside Phase 15. When Phase 16 takes them,
  `R1` as the environment value is the standard's own mechanism for a
  static link (`nested-procedures.md` §9 leaves the choice to this
  backend).

## 8. Expressions and statements

Proposals, by construct:

- **Integer arithmetic** on `SHORTINT` and `INTEGER` at their own width
  (`ADDB3`, `ADDW3`, ...), so wraparound happens at the type's width as
  poc promises, or in longwords and truncated; to be settled with the
  first fixtures. `LONGINT` uses the longword instructions; `HUGEINT` §4.
- **`DIV` and `MOD`** floor: `DIVL3` truncates toward zero, then the same
  correction the LLVM backend makes (`LLVMCodeGenerator.GenerateDivMod`),
  the remainder by `EDIV` or by multiplying back. **A zero divisor traps
  in hardware** - "a divide-by-zero trap is forced after the execution of
  an integer ... division instruction that has a zero divisor" (MACRO
  8.4.1) - which matches poc's promise that `x DIV 0` ends the program.
- **Comparisons and `BOOLEAN`**: `CMPx` then a conditional branch; a
  `BOOLEAN` value is a byte 0 or 1. `&` and `OR` short-circuit with
  branches.
- **`SET`**: a longword; `+` `BISL3`, `*` `MCOML` then `BICL3`, `-`
  `BICL3`, `/` `XORL3`; `IN` `BBS`/`BBC` (or `ASHL` and `BITL`) after a
  range check; `INCL`/`EXCL` `BBSS`/`BBCC`; a constant `{...}` an
  immediate.
- **`CASE`**: `CASEL`, the VAX's own table-driven case instruction, for a
  dense range of labels, and a chain of compares otherwise; a value with
  no label goes to the "no CASE label" trap (§9).
- **`FOR`**: `AOBLEQ`/`ACBL` where the step and types fit, otherwise
  compare and branch.
- **Arrays and records**: a field is its offset from the record's address;
  an index is checked (§9), then scaled, or used through index mode
  (`base[Rx]`), which scales by the element size itself.
- **`COPY`** and whole-array or whole-record assignment: `MOVC3`, whose
  length is a word (`MOVC3 len.rw, ...`, MACRO), so up to 65535 bytes; longer moves loop.

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

## 10. Output and fixtures

- A new option writes `<Module>.mar` beside where `-emit-llvm-ir` writes
  `.ll`, and a `-target` value selects the backend: `-emit-macro32` and
  `-target vax-dec-vms` were proposed. DCL uppercases whatever on its
  command line is not quoted (the user, 2026-10-05), so poc on VMS sees
  `-EMIT-MACRO32`. **Decided (2026-10-05): poc's options stay lowercase,
  and poc on VMS matches every option without regard to case** - all of
  them, `-build` and `-o` as much as the new ones. That is Phase 16's to
  build, since poc first runs on VMS there (`PLAN.md` Phase 16 step 4);
  option *values* that are names (modules, files) are not covered, and
  stay that step's question.
- Fixtures: `test/conformance/vax-*/` each with a `.mod`, its
  `expected-vax.mar` and, at the top of that file, a comment by the
  reviewer saying why the output is right. The harness diffs the output
  against it.
- **Decided: every `expected-vax.mar` is also assembled**, with
  `MACRO/OBJECT` on the development system - no `LINK`, no `RUN` - so the
  assembler, not only a reviewer, checks the syntax, the symbols and every
  branch's reach. This changes `PLAN.md`'s locked-in "no assembling" for
  Phase 15; linking and running stay Phase 16's. It needs a way to copy
  `.mar` files to the guest and the listing back, which is the first part
  of Phase 16 step 1 brought forward (§11, question 2).
- `VaxToolchainDriver.Mod` is a stub that writes the `.mar` and reports
  that assembling is not available (`PLAN.md` Phase 15).

## 11. Open questions

Settled 2026-10-05: the development system (§2); assembling fixtures in
Phase 15 (§10); one calling mechanism (§7); `-O2` only and
`MemoryLayout`'s record layout (§4); the stem-and-hash names (§5);
options matched without regard to case on VMS (§10).

1. **The destination machine's version** - the user is to check it.
2. **Running `MACRO` on the guest from the host**, for assembling
   fixtures. Copying is settled (2026-10-05): FTP to `192.168.2.20` as
   `poc`, active mode, the password in `~/.netrc`
   (`doc/developer/DEVELOPER.md` section 4). Running the assembler and
   bringing back its listing is not: telnet, with the password read from
   `~/.netrc`, or something UCX itself offers. It must work unattended
   from a command on the host, since the fixtures run from `make test`; on
   hosts without the guest those checks are skipped, as `doc-poc-man-page`
   is without mandoc.
3. **The hash (§5)**: 40 bits of FNV-1a in base 32, or another. A
   deliberate collision costs under a million names (§5.1); the proposal
   is to keep 40 bits and catch collisions, not to lengthen the hash.
4. **Integer arithmetic on `SHORTINT` and `INTEGER` (§8)**: at the type's
   width, or in longwords and truncated.
5. **Packed records** for VMS routines (§4) - Phase 17's, noted here.
6. **`LONGREAL`'s default format (§4)**, D_floating as VAX C, or
   G_floating - Phase 16's, noted here so the option is designed in.
7. **Collisions across a link (§5.1)**: the three layers, the `.sym`
   field carrying each symbol and the scheme's version, and `MULDEF` as
   fatal. Whether the Librarian reports `DUPGLOBAL` is to be checked on
   the development system.

## 12. Proposed order of work

Each step lands with its fixtures before the next, as Phase 8 did:

1. `VaxTypes.Mod`: sizes, offsets and the name scheme (§4, §5), with the
   name fixtures - long names, names differing only in case, module names
   with a common start, and the colliding pair of §5.1, which poc must
   reject within one module.
2. The driver option and the stub `VaxToolchainDriver.Mod`; an empty
   module's `.mar` (§6). The host-side command that copies a `.mar` to the
   development system, runs `MACRO/OBJECT` and brings the result back
   (§11, question 2), with a hand-written `.mar` first, then the empty
   module's.
3. Straight-line code: module variables, assignment, integer, `CHAR`,
   `BOOLEAN` and `SET` expressions.
4. Control flow (§3 branches, §8).
5. Procedures and calls (§7), then external `["VMS"]` procedures.
6. Arrays and records, with the traps (§9).
7. The predeclared procedures of the slice.
8. Several modules and the program's start (§6).
9. The phase record and the exit review.
