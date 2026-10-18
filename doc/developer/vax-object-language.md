# The VAX/VMS object language, as poc writes it (Phase 18) — specification

Status: a draft for `PLAN.md` Phase 18 step 1, started 2026-10-18 on the
`vax-obj` branch. It defines the subset of the VAX object language that
poc will write for its object modules: each record and subrecord, the
TIR commands, the on-disk form, and what MACRO-32 does with each
directive poc writes today. Like `vax-macro32-backend.md`, it says what
the manual fixes (a fact, with its source), what the objects MACRO makes
show (a fact, observed on the development system), and what poc chooses
(**Proposal** until the user agrees, then **Decided**). The questions
still open are in section 12.

## 1. Sources

- **The manual**: chapter 7 of the *VMS Linker Utility Manual*
  (`AA-LA62A-TE`, April 1988, VMS 5.0), "VAX Object Language", in
  `~/Reference/Computer/OS/VMS/` with a `pdftotext -layout` extract.
  No later revision of it exists for 5.x (`vax-vms-manuals-to-get.md`),
  so it is this release's. The extract is OCR'd and has errors: it gives
  `GPS$L_ALLOC` and `SDF$L_VALUE` as 1 byte, where the `L` and the real
  objects say 4. Where the extract and an object disagree, the object
  wins, and this document says so.
- **MACRO-32**: *VAX MACRO and Instruction Set Reference Manual*
  (`AA-LA89B-TE`, VMS 5.4), for what the assembler chooses: chapter 5
  (addressing modes and displacement lengths) and `.DEFAULT` in chapter
  6.
- **Real objects** (2026-10-18): eight of the Phase 15 fixtures
  (`vax-empty-module`, `-external`, `-records`, `-reals`, `-case`,
  `-procedure-values`, `-strings`, `-modules`), assembled on the guest
  by `MACRO/OBJECT/LIST` (VAX MACRO V5.4-3), then dumped with
  `ANALYZE/OBJECT` and `DUMP/RECORD`; `vax-empty-module` also with
  `MACRO/DEBUG`. Then a second set, written for what the eight do not
  use (exported and local variables, `.ADDRESS` of an external symbol,
  `.ASCID`, `.LONG` of a label and of an external, every real literal
  in the fixtures with the instruction that uses it, every short-literal
  real in `F` and `G`, a forward reference in the same psect, and 40
  externals to make the GSD outgrow a record). Every analysis reports
  no errors. Sections 3-8 cite them as "observed".

## 2. The file

- **Record format** (observed, `DIRECTORY/FULL` of MACRO's object):
  sequential organization, **variable-length records**, no record
  attributes (no carriage control), maximum record length the longest
  record. Each object-language record is one RMS record. Its first byte
  is the record type.
- **Record size**: the manual allows up to `OBJ$C_MAXRECSIZ`, 2048
  bytes, and the main module header's `MHD$W_RECSIZ` says what the
  module's longest record may be. MACRO writes 512 there, and keeps
  every record under it: with 40 externals it wrote GSD records of 491,
  491 and 462 bytes, and its TIR records stop at 461-469 bytes
  (observed). **Proposal**: poc writes 512 too, and starts a new GSD or
  TIR record before one would pass 512 bytes.
- **The file cannot be made from a byte stream on the guest.** `SET
  FILE/ATTRIBUTE` does not exist in VMS 5.5-2: `%DCL-W-IVQUAL` (tried,
  2026-10-18). FTP in binary mode makes fixed 512-byte records. So an
  object written on another system becomes an object on VMS only if
  something on VMS writes its records. `rtl/vax/Files` cannot do that:
  every file it makes is Stream_LF (`Files.Mod`, "A FILE FILES MAKES").
  See section 10.

## 3. The records poc writes

The order the manual requires (section 7.1): the main module header
(MHD) first, the language processor header (LNM) second, then any
number of GSD, TIR and TBT records, and an end of module record (EOM)
last. There must be at least one GSD record. TIR commands use psect
indexes, and a psect gets its index when its GSD subrecord is read
(first defined is 0, then 1, and so on), so a psect's definition must
come before any TIR command that names it.

**Proposal**, the order poc writes:

1. MHD, LNM, and an SRC header record (section 4).
2. One GSD record (or more, at 512 bytes) with every psect definition,
   in the order section 5.1 fixes, then every global symbol definition,
   entry point and external reference.
3. The TIR records: each psect's contents, one psect at a time.
4. The TBT records (section 7).
5. The EOM record.

MACRO interleaves its GSD and TIR records: it defines a psect, sets
the location to it, then defines the next one. The manual allows either
order, so this is a difference that does not matter (section 8).

## 4. Header records (manual 7.2)

| Record | Bytes | poc writes |
|---|---|---|
| MHD | `00` `00` (`OBJ$C_HDR`, `MHD$C_MHD`); `MHD$B_STRLVL` 0; `MHD$W_RECSIZ` 512; the module name as a counted string (1-31 characters); the version as a counted string (2-32 bytes, a count and 1-31 characters); the creation time, 17 characters, `dd-mmm-yyyy hh:mm`; the time of last patch, 17 bytes | name: the `.TITLE` name (the module's name, uppercase); version: the `.IDENT` text, the module key, **uppercase**, as MACRO stores it (observed: `.IDENT /51674813eee7e6ad/` is stored as `51674813EEE7E6AD`) |
| LNM | `00` `01`, then the processor's name and version with no count | `Peaseblossom poc <version>` (MACRO: `VAX MACRO V5.4-3`) |
| SRC | `00` `02`, then text with no count; ignored by the linker, shown by `ANALYZE/OBJECT` | the source file's name (MACRO puts its own command line here) |

The manual says the last-patch field "should be padded with 17 zeros".
MACRO fills it with 17 spaces (observed, record 1 of every object). The
linker ignores it. **Proposal**: 17 spaces, as MACRO does, so that the
header compares equal byte for byte.

MACRO also writes a title header (TTL, `00 03`, text `". "`). It is
ignored, and poc leaves it out.

## 5. Global symbol directory (manual 7.3)

A GSD record is `01` (`OBJ$C_GSD`) followed by subrecords, each
beginning with its type byte. poc uses three subrecord types.

### 5.1 Program section definition, `GSD$C_PSC` (0)

| Field | Bytes | Value |
|---|---|---|
| `GPS$B_GSDTYP` | 1 | 0 |
| `GPS$B_ALIGN` | 1 | the alignment as a power of 2: 0 byte, 2 long, 3 quad |
| `GPS$W_FLAGS` | 2 | bit 0 PIC, 2 OVR, 3 REL, 4 GBL, 5 SHR, 6 EXE, 7 RD, 8 WRT |
| `GPS$L_ALLOC` | 4 | the module's contribution in bytes |
| `GPS$B_NAMLNG`, `GPS$T_NAME` | 1 + 1-31 | the name |

The psects poc writes, with the flags MACRO gives them (observed):

| Index | Name | `.PSECT` attributes | Flags (hex) | Align |
|---|---|---|---|---|
| 0 | `.  ABS  .` | (MACRO's own, for absolute symbols) | `0000` | 0 |
| 1 | `POC_CODE` | `PIC,SHR,NOWRT,EXE,LONG` | `00E9` (PIC REL SHR EXE RD) | 2 |
| 2 | `POC_CONST` | `PIC,SHR,NOWRT,NOEXE,QUAD` | `00A9` (PIC REL SHR RD) | 3 |
| 3 | `POC_DATA` | `NOPIC,NOSHR,WRT,NOEXE,QUAD` | `0188` (REL RD WRT) | 3 |
| 4 | `POC_ADDR` | `PIC,NOSHR,NOWRT,NOEXE,LONG` | `0089` (PIC REL RD) | 2 |

`POC_ADDR` is defined only in a module that uses it
(`vax-macro32-backend.md` section 6). The absolute psect `.  ABS  .` is
where a symbol defined by `==` with a constant value lives (section
5.2). **Proposal**: poc defines these psects in this order, as MACRO
does, so that the psect indexes in the two objects agree, which makes
them easier to compare.

### 5.2 Global symbol definition and reference, `GSD$C_SYM` (1)

A definition (`GSY$V_DEF` = 1):

| Field | Bytes | Value |
|---|---|---|
| `SDF$B_GSDTYP` | 1 | 1 |
| `SDF$B_DATYP` | 1 | 0 (ignored by the linker) |
| `SDF$W_FLAGS` | 2 | bit 1 DEF, bit 3 REL if the symbol is relocatable |
| `SDF$B_PSINDX` | 1 | its psect |
| `SDF$L_VALUE` | 4 | its offset in the psect, or its value if absolute |
| `SDF$B_NAMLNG`, `SDF$T_NAME` | 1 + 1-31 | the name |

A reference (`GSY$V_DEF` = 0) has neither the psect nor the value:
type, data type, flags (all 0), name.

What poc defines and refers to:

- **The module key**, `POC_K1_<KEY> == 0`: a definition in psect 0,
  not relocatable, value 0 (observed).
- **An exported variable**, labelled `<SYMBOL>::` in `POC_DATA`: a
  relocatable definition in psect 3, its offset as the value
  (observed). A local label (`:`) is not in the GSD at all.
- **Every external symbol** poc declares `.EXTERNAL` (imported `_INIT`
  routines, keys, variables and procedures, and `["VMS"]` routines): a
  reference (observed in `vax-external`). The manual does not say
  whether a symbol that a TIR command names with `TIR$C_STA_GBL` must
  also have a reference in the GSD. MACRO always writes one, and poc
  will too.

The weak, universal and word-psect forms are not used. A universal
symbol is made by `LINK`'s `UNIVERSAL=` option (Phase 17), not in the
object.

### 5.3 Entry point and mask, `GSD$C_EPM` (2)

The symbol definition's fields, with a 2-byte entry mask (`EPM$W_MASK`)
between the value and the name. Each `.ENTRY` makes one: DEF and REL
set, psect 1, its offset, the register-save mask (observed). `.ENTRY`
makes the symbol global (MACRO 5.4, `.ENTRY`).

The manual (7.3.3) says the language processor "uses a TIR command to
direct the linker to insert the mask" at the entry point. MACRO stacks
the mask with `TIR$C_STA_UB`, before the GSD record that defines the
entry point, and stores it with `TIR$C_STO_W` after (observed). The
mask is a constant, so poc writes the word with a Store Immediate
instead. The bytes in the image are the same (section 8).

## 6. Text information and relocation (manual 7.4)

A TIR record is `02` (`OBJ$C_TIR`) followed by commands. The linker
runs them on its second pass, against a stack of longwords and a
location counter. Values on the stack stay there across records, but
the stack must be empty at the EOM record. The commands poc uses (the
codes are the manual's):

| Code | Command | Use |
|---|---|---|
| < 0 | Store Immediate | `-n`, then n bytes (1-128), written as they are: every byte the module fixes itself, opcodes, operand specifiers and resolved displacements included |
| 0 | `STA_GBL` | push a global symbol's value (counted name) |
| 4 | `STA_PB` | push psect base + signed byte offset (psect index 1 byte) |
| 5 | `STA_PW` | psect base + signed word offset |
| 6 | `STA_PL` | psect base + signed longword offset |
| 7 | `STA_UB` | push an unsigned byte (a constant to add) |
| 3 | `STA_LW` | push a longword constant (MACRO, for a constant in a `.LONG` list that also holds a symbol; poc writes a constant as a Store Immediate) |
| 22 | `STO_LW` | store a longword: `.LONG` of a symbol, with no fixup for a shareable image |
| 25 | `STO_LD` | store top − (location + 4): a longword displacement |
| 27 | `STO_PIDR` | store a position-independent data reference: an address in data, which the image activator fixes up when the image is shareable |
| 28 | `STO_PICR` | store a position-independent code reference: writes `9F` and the absolute address if the target is absolute, `EF` and a longword displacement if it is relocatable, `FF` and a displacement to the transfer vector if it is in a shareable image. It writes the operand specifier byte itself |
| 51 | `OPR_ADD` | add the top two longwords |
| 80 | `CTL_SETRB` | set the location counter to the top longword (a psect base + offset) |
| 81 | `CTL_AUGRB` | add a signed longword to the location counter: skips space, as `.BLKx` and `.ALIGN` do |

### 6.1 What each kind of reference becomes (observed)

These are the only patterns in the eight objects:

| In the `.mar` | MACRO's TIR commands |
|---|---|
| a label in another psect, or later in the same psect, bare (`PUSHAB L_MODULE_NAME`, `BLBS L_INITIALISED, ...`) | Store Immediate `EF`; `STA_PB`/`STA_PW` psect, offset; `STO_LD` |
| the same, plus a constant (`X+4`) | `STA_PB`; `STA_UB` n; `OPR_ADD`; `STO_LD` |
| a label earlier in the same psect, bare | resolved by MACRO: `AF` + byte or `CF` + word displacement, in a Store Immediate |
| `G^<external>` | `STA_GBL` name; `STO_PICR` |
| `G^<external>+n` | `STA_GBL`; `STA_UB` n; `OPR_ADD`; `STO_PICR` |
| `L^<label>` (`JMP L^L_9`) | `EF`; `STA_PB`; `STO_LD` |
| `.ADDRESS <label>` (type descriptors, in `POC_ADDR`) | `STA_PB`/`STA_PL`; `STO_PIDR` |
| `.ADDRESS <label>+n` | `STA_PB`/`STA_PL`; `STA_UB` n; `OPR_ADD`; `STO_PIDR` |
| `.ADDRESS <external>` (an imported type descriptor), `+n` | `STA_GBL`, (`STA_UB` n, `OPR_ADD`); `STO_PIDR` |
| `.ASCID` | the descriptor's first longword in a Store Immediate (length, `DSC$K_DTYPE_T` 14, `DSC$K_CLASS_S` 1); its address `STA_PB` + `STO_PIDR`; the text in a Store Immediate |
| `.LONG <label>`, `.LONG <external>` (the `SOR$` constants) | `STA_PB` or `STA_GBL`; `STO_LW` |
| `.WORD L_a-L_b` (a `CASE` table) | `STA_PB` a; `STA_PB` b; `OPR_SUB`; `STO_W` |
| `.BYTE 0[n]` and similar | `STA_UB` 0; `STA_UB` n; `STO_RB` (which the linker skips for zero: manual 7.4) |
| `.BLKx`, `.ALIGN` | `CTL_AUGRB` |
| `.PSECT` switch | `STA_PB` psect, 0 (or `STA_PW` with the offset reached); `CTL_SETRB` |

An index register after a relative operand (`X[R0]`) is the index byte
`4x` in front of the `EF`, in the same Store Immediate (observed:
`00000078'EF40`).

**Proposal**: poc writes these patterns with three simplifications that
give the same image:

- A displacement or a label difference between two labels in the same
  psect is a constant, so poc computes it and writes it in a Store
  Immediate. MACRO leaves a forward one to the linker, as with the
  `CASE` table's `.WORD L_3S-L_6`.
- The offset in `STA_Px` is always the smallest form that fits (`PB`,
  `PW`, `PL`), as MACRO's are.
- Zeros (`.BLKx`, padding, zero-filled data) are skipped with
  `CTL_AUGRB`, never stored, so the linker can leave the page demand-zero
  (manual 7.4, the note on `STO_RB`).

### 6.2 Displacement lengths: MACRO does not relax

MACRO 5.4 section 5.2: "If no displacement length specifier precedes
the address expression, and the value of the expression is known, the
assembler chooses the smallest number of bytes (1, 2, or 4) needed ...
If the address expression is either defined later in the program or
defined in another program section, the assembler considers the value
unknown". An unknown value takes the default length, which is a
longword unless `.DEFAULT` says otherwise (MACRO 5.4, `.DEFAULT`, note
2), and poc writes no `.DEFAULT`. The objects agree: `CALLS #0,
VAXEMPTY_INIT`, a backward reference, is `AF E9` (a byte); `MOVAB
VAXPROCVALS_MUL_..., (R0)`, a backward reference, is `CF F57D` (a word);
a reference forward or into another psect is always `EF` (a longword),
the second set's `MOVAB L_FWD, R3` and `CALLS #0, OBJSET2_LATER`, both
forward in `POC_CODE`, included.

So **to be byte-identical with MACRO, poc's encoder needs no relaxation
to a fixpoint.** `PLAN.md` step 3 assumed it would. The rule is one
pass: a backward reference in the same psect gets the shortest
displacement that reaches, and every other reference gets a longword.
Branch instructions (`Bxx`, `BRB`, `BLBS`) have a fixed displacement
size, and poc already writes them only over short, fixed distances
(`vax-macro32-backend.md` section 3). **Decided** (the user,
2026-10-18): the encoder follows MACRO's rule. Relaxing forward references to get shorter code is an
optimization for later, and it would end the byte-for-byte comparison.

### 6.3 Literals

MACRO 5.4 section 5.1.8, note 1: for `#value` the assembler uses short
literal mode when the value fits, and immediate mode when it does not,
or when it is relocatable or not yet defined. For an integer, that is
0-63. For `F_floating`, `D_floating` and `G_floating`, it is the 64
values that a 3-bit exponent and a 3-bit fraction can represent
(0.5 to 120, `MOVF #0.625, R6` is its example). **Proposal**: poc
chooses the same way. That means poc converts its real literals to
`F_floating` and `G_floating` bits itself, which MACRO does today from
the decimal text poc writes.

How MACRO rounds (observed, 2026-10-18): all 191 real literals of the
second set, as `MOVF` or `MOVG` operands, are exactly what correct
rounding of the decimal value, half to even, gives. Both are the
format `0.1f × 2^(e − bias)` with the hidden bit, the bias 128 for `F`
(8-bit exponent, 23-bit fraction) and 1024 for `G` (11 bits, 52), and
the 16-bit words in memory most significant first, each little-endian.
So an `F` value's bits are IEEE single's with the exponent 2 greater,
and a `G` value's IEEE double's likewise (for a value both can hold).
The same holds for the data directives: `.F_FLOATING 0.1` is
`CC 3E CD CC`, and the smallest normal `F`, `-2.9387359E-39`, is
`80 80 00 00`. The short literal, when the value is one of its 64, wins
over immediate mode. Not yet seen: `#0.0`, which a short literal cannot
hold (literal 0 is 0.5), so it must be immediate mode or `CLRx`.

## 7. Traceback records (manual 7.8)

MACRO writes TBT records by default, without `/DEBUG` (observed: three
in every object, 138 bytes for `vax-empty-module`). With them, a
condition the program does not handle prints the names of the routines
on the stack. A TBT record is `05`, followed by TIR commands that build
debug symbol table (DST) records. Their format is not in the Linker
manual. What the objects show, one DST record each (length byte not
counting itself, then type):

| DST type | MACRO writes | Bytes observed |
|---|---|---|
| `BC` module begin | at the start | length, `BC`, flags 0, language (4 bytes, 0 for MACRO), the module name as a counted string |
| `BE` routine begin | for each `.ENTRY` | length, `BE`, flags 0, the address (`STA_PL`/`STA_PB` + `STO_PIDR`), the name as a counted string |
| `B8` psect | for each psect | length, `B8`, flags 0, the address (`STO_PIDR`), the name as a counted string, the size (4 bytes) |
| `BD` module end | at the end | `01 BD` |

There is no routine-end record and no line-number (PC-correlation)
record in the TBT records. Those come only with `MACRO/DEBUG`, in DBG
records (`06`), along with the source file's name. **Proposal for step
5**: poc writes the same TBT records as MACRO, so that a traceback names
the module and routine as it does today, and DBG records besides
(section 11).

## 8. End of module (manual 7.5)

`03` (`OBJ$C_EOM`), the severity (0), and, in the main module only, the
psect (1) and offset of the transfer address, `<MODULE>_MAIN`. That is 7
bytes, without the optional transfer-flags byte, as MACRO writes it
(observed). Any other module's EOM is 2 bytes.

## 9. Comparing poc's object with MACRO's

The two objects will not be equal byte for byte. These legitimate
differences are listed now, so that a test can allow exactly them:

1. The header: the creation time, the LNM text, the SRC text, and
   MACRO's TTL record.
2. The order of the GSD and TIR records (section 3), and how they are
   split into records.
3. How a value is built: a constant poc resolves itself (section 6.1)
   where MACRO uses `STA_PB` `STA_PB` `OPR_SUB` `STO_W`; the entry mask
   as a Store Immediate instead of `STA_UB` and `STO_W`; zeros skipped
   instead of stored.

What must be equal is what the linker makes of the two objects: every
byte of every psect, every relocation, every symbol and its value, the
entry masks and the transfer address. **Proposal**, the comparison for
steps 3 and 4: a host-side tool that reads an object (the `DUMP/RECORD`
text of MACRO's, or poc's own file) and runs its TIR commands. It
produces, for each psect, the bytes and a list of relocations (offset,
kind: `LD`, `PIDR`, `PICR`, and the target: psect + offset or global +
addend), and for the module its symbols, psects and transfer address.
Two objects are equivalent when those lists are equal. `LINK` and run
remains the final test (step 4), as `PLAN.md` says.

The DUMP of MACRO's objects comes back as text by `tools/vax-do`, so
this needs no binary transfer from the guest.

## 10. Writing the records (Decided, 2026-10-18)

The user agreed to section 2's consequence on 2026-10-18:

- **On VMS**, poc writes `<MODULE>.OBJ` itself, a record at a time.
  A routine in `PocRtl.mar`, under a small VAX-only module, creates a
  sequential file with variable-length records (`FAB$C_VAR`), no record
  attributes, and the maximum record size of section 2, and `$PUT`s each
  object-language record as one RMS record. Only poc's object writer
  uses it. It sits beside `Files`, whose interface stays voc's. A compile
  on the VAX then makes the object directly, with no MACRO and no
  conversion step: what `PLAN.md` step 6 makes the default on VMS, and
  what step 7's V1/V2/V3 fixed point runs.
- **On another system** (a cross-compile on atla or a BSD), poc writes
  the same records in the form VMS keeps a variable-length file on disk:
  for each record a 2-byte little-endian count, the bytes, and a pad byte
  when the count is odd. FTP in binary mode puts that file on the guest
  as fixed 512-byte records, and a small program built with poc reads it
  with `Files` (which reads a fixed-length file as its bytes) and writes
  the records with the same routine. The tools that run fixtures on the
  guest (`tools/vax-do`, `vax-run`) call it for each `.OBJ` they send.
- The object writer is one module whatever the system: it hands each
  record to an interface with the two implementations, so the records
  written on VMS and elsewhere are the same bytes.

## 11. Debugger information (DBG records)

**A requirement** (the user, 2026-10-18): a program poc builds must be
debuggable in the VMS 5.5-2 debugger (`LINK/DEBUG`, `RUN`, then source
lines, breakpoints, stepping, routine names, and variables with their
types). `PLAN.md` step 5 asked whether to do that; it is now decided
that it is done, and step 5 decides how. That goes beyond MACRO, whose
DBG records describe only its labels and the `.MAR` file's lines.

What is known so far:

- The DBG records (`04`) are TIR command streams that build debug
  symbol table (DST) records, as the TBT records do (manual 7.7). The
  linker only copies them, with `/DEBUG`, so their content is between
  poc and the debugger.
- The DST record format is not in the Linker manual or any 5.x manual we
  have; it is in the debugger's source, `DSTRECRDS.REQ` (section 12,
  question 1). The guest has part of it: `SYS$LIBRARY:STARLET.MLB` holds
  `$DSTDEF`, and `SYS$LIBRARY:DSTDEF.H` its C form, but both define
  only the DST location-expression commands (`DST$K_STA_R00`..
  `DST$K_OPR_STOP`: stack a register, an immediate, add, fetch, stop),
  which describe where a variable is, not the record types.
- The record types in MACRO's output (section 7: module begin `BC`,
  routine begin `BE`, psect `B8`, module end `BD`, and with `/DEBUG` a
  source-file record and line-number records) are the start.
- The guest has four compilers that write DBG records with `/DEBUG`:
  VAX C (`VAXC.EXE`), FORTRAN, BASIC and Ada (`SYS$SYSTEM`). Their
  objects, for small programs with records, arrays, pointers, enumerations,
  nested routines and locals in registers and on the stack, show the
  records a real compiler writes for each, and the debugger on the
  guest (`DEBUG.EXE`, `DEBUGSHR.EXE`) shows whether poc's are read the
  same way.

**Proposal for step 5**: from the DST record definitions (section 12,
question 1), and from dumps of those compilers' DBG records for programs
that cover what poc needs, write down here the subset poc writes, and
test each piece in the debugger on the guest: first module, routine and
line numbers (breakpoints and `STEP` by Oberon line), then variables of
the basic types, then records, arrays, pointers and procedure types.
The front end already gives every node a line and column; the code
generator must carry them down to each instruction it emits, which
step 2's instruction representation should hold from the start.

## 12. Open questions

1. **The DST record definitions** for section 11: **found**
   2026-10-18, `DSTRECRDS.REQ` (V04-000, 1984), the debugger's own
   definition file for the DST the VAX compilers write, from the VMS 4.0
   source listings on bitsavers (`vax-vms-manuals-to-get.md`, "Still to
   find"). It is 4.0's, not 5.5-2's, so each record poc writes is
   checked against the 5.5-2 debugger on the guest and against the DBG
   records of the guest's compilers. To do: read it and write here the
   subset poc needs.
2. **`#0.0`** in `MOVF`/`MOVG`, the one real literal not yet seen
   (section 6.3).
3. **The module-begin record's language** (`DST$L_MODBEG_LANGUAGE`, 4
   bytes) is 0 (MACRO) in MACRO's objects. `DSTRECRDS.REQ` defines the
   codes, among them `DST$K_PASCAL` = 6, `DST$K_C` = 7, `DST$K_ADA` = 9
   and `DST$K_UNKNOWN` = 16, "an escape" for a language the debugger does
   not support, which then gets whatever support DEBUG gives an unknown
   language. The debugger chooses its expression syntax and how it
   shows values by this code. To decide in step 5, by trying both on the
   guest: `DST$K_UNKNOWN`, or `DST$K_PASCAL`, whose syntax (`r.f`,
   `p^`, `a[i]`, `:=`) is nearly Oberon's.
