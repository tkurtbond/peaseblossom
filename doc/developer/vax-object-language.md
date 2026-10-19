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
   (section 6.3): **answered** 2026-10-18 (section 14.7), immediate
   mode and zeros, as long as the operand.
3. **The module-begin record's language** (`DST$L_MODBEG_LANGUAGE`, 4
   bytes) is 0 (MACRO) in MACRO's objects. `DSTRECRDS.REQ` defines the
   codes, among them `DST$K_PASCAL` = 6, `DST$K_C` = 7, `DST$K_ADA` = 9
   and `DST$K_UNKNOWN` = 16, "an escape" for a language the debugger does
   not support, which then gets whatever support DEBUG gives an unknown
   language. The debugger chooses its expression syntax and how it
   shows values by this code. To decide in step 5, by trying both on the
   guest: `DST$K_UNKNOWN`, or `DST$K_PASCAL`, whose syntax (`r.f`,
   `p^`, `a[i]`, `:=`) is nearly Oberon's.

## 13. Step 2: the instruction representation (decided 2026-10-18)

`PLAN.md` step 2: before anything is encoded, `VaxCodeGenerator` builds
what it writes as data, and a printer turns the data into exactly the
`.mar` it writes today. Nothing about the emitted assembly may change.

### 13.1 What the generator does today

- A procedure's body is already built as a list before it is written,
  so that the entry mask and the frame's size are known first: one
  `Instruction` per line, a label, a comment or an instruction, but each
  holding its mnemonic and operands **as text** (`op: ARRAY 32 OF CHAR;
  operands: ARRAY 160 OF CHAR`), and `WriteBody` prints them.
- Operands are already structured until the last moment: an `Operand`
  is an immediate (integer, set, or a real's text), a register (or a
  pair), or memory (a symbol and offset, or an offset from FP, AP or a
  base register, deferred or not, with an index register), and `Text`
  and `HalfText` flatten it. 27 `Emit1`, 105 `Emit2`, 31 `Emit3`, 44
  `EmitTo` and 5 `EmitBranch` calls go through them.
- 235 `Emit` calls build their operand text by hand
  (`COPY("#", text); AppendInt(text, n); Append(text, ", R0")`), and two
  places look at text to decide (`from = "#^X00000000"`, `text[0] =
  "#"`).
- Outside the bodies, 83 `Line(w, ...)`, 11 `Label(w, ...)` and 35
  `WriteStr(w, ...)` calls write the module's layout and data straight
  to the file: the title, the psects, the variables, the string and
  structured constants, the type descriptors, the module descriptor,
  the initializer and the program's start.

### 13.2 The subset of MACRO-32 poc writes

Taken from 490,902 lines: poc's own source with `rtl/vax`, compiled for
the VAX (`tools/bootstrap/vax-v1`, 35 modules, 241,646 lines), and every
fixture's `.mar` but the hand-written ones (2026-10-18).

- **Instructions** (134): `MOVL PUSHL JMP CALLS CALLG PUSHAB BNEQ MOVAB
  CMPL RET CLRL SUBL2 MOVB TSTL CLRQ BLEQU MOVAQ MOVQ CLRB BLBS BEQL
  ADDL2 BLSS CVTWL BGTR SUBL3 BLSSU ADDL3 MULL2 BLBC INCL MOVZBL MULL3
  MOVC3 BGEQ MOVW ADWC DECL BGEQU MOVC5 CMPB SBWC ASHL BICL2 BLEQ CMPW
  MOVG TSTB DIVL3 LOCC TSTW XORL2 INCW SUBW3 CLRW MOVF BICB3 MNEGL CMPG
  CVTLB DECW BGTRU ADDW2 MULW3 ASHQ BRB MOVZBW PUSHAL ADDW3 CVTLW XORL3
  DIVW3 CVTWB TSTG BISL2 MULW2 CMPF MULG2 SUBW2 XORW2 CVTLG CVTFG MNEGG
  CVTGL BBC TSTF XORB3 MULG3 MOVZWL CVTBL BVC MNEGW EMUL ADDG2 SUBG3
  MULF3 MNEGF CLRG XORB2 ADDG3 DIVG3 ADDF2 MCOML CVTLF SUBG2 CLRF CVTBW
  CVTFL DIVG2 DIVF3 CASEL SUBF3 MULF2 INCB CVTGF BICL3 ADDF3 SUBB2 CVTWG
  CVTWF ADDB2 SUBF2 SUBB3 ROTL MOVAW DIVF2 DECB BISL3 MULB2 MNEGB ADDB3
  CASEW PUSHAQ CASEB`. Several mnemonics are composed from a stem and a
  size letter, so the set is checked against the generator's source as
  well when the encoder's opcode table is written (step 3): a mnemonic
  outside the table is an error at compile time, not a wrong byte.
- **Operand forms** (with their counts): `-n(Rn)` 172,648, `#n`
  140,206, `Rn` 105,475, a bare symbol (a label, branch target or local
  variable: relative mode) 91,389, `G^sym` or `L^sym` 49,454, `n(Rn)`
  32,476, `(Rn)` 9,439, `#^X<hex>` 5,652, `@n(Rn)` 3,927, `@n(Rn)[Rx]`
  1,669, `sym[Rx]` 1,659, `#-n` 1,272, `-n(Rn)[Rx]` 1,028, `@-n(Rn)` 863,
  `sym+n` 717, `@-n(Rn)[Rx]` 428, `n(Rn)[Rx]` 387, `#<real>` 330,
  `-(SP)` 289, `#-<real>` 151, `(Rn)[Rx]` 54, `sym+n[Rx]` 8,
  `G^sym[Rx]` 2, `G^sym+n` 2. No autoincrement, no `S^`/`I^`, no `B^`
  or `W^`, no deferred relative.
- **Directives**: `.TITLE .IDENT .PSECT .ENTRY .EXTERNAL .WORD .LONG
  .BYTE .ADDRESS .ASCII .ASCIZ .ASCIC .ASCID .BLKB .BLKW .BLKL .BLKQ
  .BLKF .BLKG .ALIGN .F_FLOATING .G_FLOATING .END`, a direct assignment
  `sym == value`, labels `sym:` and `sym::`, and a `.WORD` entry mask
  `^M<...>` for a private procedure.

### 13.3 Decided (the user, 2026-10-18)

1. **A module of its own, `src/back/vax/VaxInstructions.Mod`**, holding
   the data and the printer, so that the encoder (step 3) and the object
   writer (step 4) use it without `VaxCodeGenerator`:
   - `Specifier`: a register; `(Rn)`; `-(Rn)`; `d(Rn)` and `@d(Rn)`; a
     literal or immediate `#v` (an integer, printed decimal or as
     `^X` and eight hex digits as written today, or a real, kept as the
     text poc writes with its type, `F` or `G`, for step 3's conversion);
     relative `sym+n`, with the prefix `G^` or `L^` or none; any of the
     memory forms with an index register `[Rx]`.
   - `Line`: an instruction (mnemonic, up to six specifiers, or a label
     as a branch's last), a label (local `:` or global `::`), a directive
     with its items (numbers, symbols, symbol differences, strings, the
     mask), a direct assignment, or a comment; each with the **source
     line and column** of the statement it came from (0 for none), which
     the printer ignores and step 5 needs.
   - `Print(VAR w: Files.Rider; line: Line)`, writing the text as
     `Line`, `Label` and `WriteBody` do now.
2. **One list per module.** The bodies' lists and the 83 direct `Line(w,
   ...)` calls both become lines appended to a module-wide list, in the
   order written today, and the file is printed from it at the end. The
   encoder will read the same list.
3. **Incremental, with the output unchanged after each piece.** A line
   may hold legacy text while the conversion goes on, printed as now:
   - 2a: `VaxInstructions`, the printer, and the generator's list made of
     its lines, every line still text.
   - 2b: `Text`/`HalfText` become a `Specifier` builder, and the `EmitN`
     calls structured.
   - 2c: the 235 hand-built `Emit` calls, in batches by area (moves and
     arithmetic, calls and argument lists, traps and checks, strings and
     block moves, sets and shifts, reals, procedures and entry), with
     the two text tests rewritten as tests of the specifier.
   - 2d: the module's layout and data, from `Line(w, ...)` to directive
     lines.
   - 2e: the legacy text form removed, so that nothing can go round the
     representation again.
4. **The safety net for each piece**: `make check` (every VAX fixture
   compares its output with the reviewed `expected-vax.mar` and its
   imports'), and the whole V1 corpus above: `tools/bootstrap/vax-v1` run
   before the step and after each piece, the 35 `.mar` files compared with
   `cmp`. The corpus, poc's own source, reaches far more of the generator
   than the fixtures do. Any difference stops the piece.
5. **The source position.** The generator sets the current statement's
   line and column as it starts each statement (and each procedure's
   entry and exit), and every line it appends takes them, so step 5 has
   a position for every instruction without a second change of every
   call site.

## 14. Step 3: the instruction encoder (decided 2026-10-18)

### 14.1 What it takes and what it gives

The encoder reads the module's line list (section 13.3), unchanged, and
gives the module as the linker would see it, before any record is
written:

- the program sections, in the order of their first `.PSECT`, each with
  its name, attributes and alignment, its size, and its bytes;
- for each section, a list of **relocations**: the offset, the kind (the
  four of section 9: `LD`, a longword displacement; `PICR`, a `G^`
  operand, its specifier byte included; `PIDR`, an `.ADDRESS`; `LW`, a
  `.LONG` of a symbol), and the target, a section and offset or an
  external symbol and an addend;
- the symbols: each label with its section and offset, which of them
  are global (`::` and `.ENTRY`), the direct assignments (`POC_K1_... ==
  0`, absolute), and the external symbols referenced;
- the entry points (`.ENTRY`) with their register masks, the title and
  ident, and the transfer address (`.END <sym>`).

Step 4 writes that as records; step 3's test compares it (section 14.5).
Nothing else in poc changes: `-emit-mar` and the build through MACRO
stay as they are until step 6.

### 14.2 Modules

- **`src/back/vax/VaxOpcodes.Mod`**: the opcode table. For each mnemonic
  the encoder accepts, its opcode (one byte, or two: the `G_floating`
  instructions are `FD` and a byte, `MOVG` is `50FD`) and its operands,
  each an access type (read, modify, write, address, field base, branch)
  and a data type (`B W L Q F G`), which give an immediate's size and a
  branch displacement's. The entries are the 138 mnemonics of section
  13.2 and any other the generator can compose from a stem and a size
  letter (found by reading the generator, not only its output), taken
  from VAX MACRO 5.4's Appendix D (the 5.4 MACRO manual, already the
  source of section 6.2) and Chapter 9. A mnemonic outside the table is
  a compile-time error, never a guessed byte.
- **`src/back/vax/VaxEncoder.Mod`**: the encoder, and a printer of its
  result as text (section 14.5).
- **`src/front/DecimalToDouble.Mod`** gets one new exported procedure,
  `Rounded`'s result as the integer `m` and binary exponent `e` (`m *
  2^e`) instead of a `LONGREAL`, so that `F` and `G` bits are built from
  integers, exactly, whatever the host's floating point (section 14.4).
  `Rounded` already takes the precision and the exponent range as
  parameters, so the rounding is the code the front end uses today.

### 14.3 Layout, in one pass

The encoder walks the lines once, keeping a location counter for each
section:

- A **label** takes the current section and offset. A label defined
  twice is an error.
- An **instruction** is its opcode, then each operand's specifier, in
  order, with an index register's `4x` byte first. Every length is
  known as the specifier is written:
  - a register, `(Rn)`, `-(Rn)`: one byte;
  - `d(Rn)`, `@d(Rn)`: the shortest displacement that holds `d` (`A`/`C`/`E`
    and their deferred forms `B`/`D`/`F`), as MACRO picks for a known
    value (MACRO 5.4, section 5.2: "the smallest number of bytes");
  - `#v`: a short literal when MACRO's rule allows (section 6.3: an
    integer 0-63, or a real that is one of the 64), otherwise `8F` and
    the value in as many bytes as the operand's data type has (8 for a
    quadword or `G`). A number in a real operand, an integer too, is
    converted to the operand's type first (MACRO 5.4, section 5.2.4,
    note 3, "Numeric values are converted"; observed, section 14.7):
    `MULG2 #10, R0` is the short literal `22`, 10.0, never 10's bits;
  - a relative operand (a bare symbol, `L^`): section 6.2's rule. A
    symbol already defined, earlier in the same section, gets the
    shortest displacement from the end of the specifier (`AF`, `CF`,
    `EF`); every other one, and every `L^`, gets `EF` and a longword;
  - `G^sym`: five bytes, a `PICR` relocation (the linker writes the
    specifier byte itself, section 6);
  - a branch operand: the displacement the opcode fixes (a byte for
    `Bxx`/`BRB`/`BLBx`/`BBC`, a word for none poc writes today), from
    the end of the instruction.
- A **forward reference** in the same section (an `EF` longword, a
  branch, a `CASE` table's `.WORD L_a-L_b`) is kept on a list and
  filled in when the section ends, as the constant it then is (section
  6.1's first simplification). A reference into another section is an
  `LD` relocation with section and offset. A branch that does not reach,
  or a difference of two labels in different sections, is an error in
  poc (a generator bug), not a wrong byte.

Because a length never depends on a later label, one pass fixes every
offset, and the lists only fill in values.

### 14.4 Directives, data and reals

| Line | Encoded as |
|---|---|
| `.TITLE`, `.IDENT` | kept for the header (step 4); no bytes |
| `.PSECT name[, attributes]` | the section is created (attributes, alignment) or resumed at its counter |
| `.EXTERNAL sym, ...` | the symbols, as references |
| `.ENTRY name, ^M<...>` | a global symbol and an entry point; the 2-byte mask (bits 0-11 the registers) as data |
| `.WORD ^M<...>` | the 2-byte mask |
| `.BYTE`, `.WORD`, `.LONG` of numbers (`v[n]` repeated), hex | the bytes, little-endian |
| `.LONG sym[+n]` | four zero bytes and an `LW` relocation |
| `.WORD L_a-L_b` | the difference, in the same section (filled in later when forward) |
| `.ADDRESS sym[+n]` | four zero bytes and a `PIDR` relocation |
| `.ASCII`, `.ASCIZ`, `.ASCIC` | the text; with a final `0`, or a leading count byte |
| `.ASCID` | the descriptor (length word, `14`, `1`), its address `PIDR` to the text that follows, the text |
| `.BLKB/W/L/Q/F/G n` | `n` times the size, zeros (step 4 skips them, section 6.1) |
| `.ALIGN LONG`, `.ALIGN WORD` | zeros to the boundary (poc writes it only in data sections, section 14.7) |
| `.F_FLOATING`, `.G_FLOATING` | the reals' bits |
| `sym == value` | an absolute symbol |
| `.END [sym]` | the transfer address |

**Reals.** A real literal's text, as poc wrote it, is rounded by
`DecimalToDouble` to 24 bits (`F`) or 53 (`G`), half to even, giving
`m` and `e` with the value `m * 2^e`. No VAX real is subnormal, so
the exponent range is the format's normal range; a value outside it is
an error. The bits are those of section 6.3: `F` is the sign, the
exponent `e + 24 + 128` in 8 bits and the 23 fraction bits below the
hidden one, `G` the sign, `e + 53 + 1024` in 11 bits and 52 fraction
bits; the 16-bit words go most significant first, each little-endian.
The value is a **short literal** when it is `(8 + f)/16 * 2^x` with `x`
and `f` each 0-7 (0.5 to 120): the literal byte is `x * 8 + f`. `#0.0` is not one of them (literal 0 is 0.5), so it is
immediate mode and zeros (section 14.7).

### 14.5 Testing: the image, compared with MACRO's

The encoder's result is printed as text by a new option, `poc
-emit-vax-image` (beside `-emit-mar`, for the fixtures and debugging):
for each section its attributes, its bytes in hex with offsets, and its
relocations, then the symbols, entry points and transfer address, each
in a fixed order. A section's zero bytes print as such; step 4's skipping
of them is not visible here.

MACRO's object gives the same text through a host-side program, the
section 9 tool: it reads `DUMP/RECORD`'s output for an object (as text,
so nothing binary comes back from the guest), runs the TIR commands into
section bytes and relocations, and prints them the same way. It is
written in Oberon and built with poc, `tools/vax-image/ObjectImage.Mod`
(`make vax-image` builds `build/bin/vax-image`), so that step 4 can
reuse its reader for poc's own objects (it reads a binary object too).
The image and its printer are a module of their own,
`src/back/vax/VaxImage.Mod`, which the encoder fills as the tool
does, so the two images are printed by the same code.

- **Fixtures.** Each VAX fixture with an `expected-vax.mar` gets an
  `expected-vax.image`, made once from MACRO's object for that `.mar` on
  the guest (`tools/vax-macro-image`, through `vax-do`),
  reviewed the way the `.mar` was, and committed. Its `test.sh` then
  compares `poc -emit-vax-image` with it, with no guest needed, so `make
  check` covers the encoder on every host. When a fixture's `.mar`
  changes, its image is made again from MACRO, never from poc.
- **The corpus.** poc's own source for the VAX, the 35 modules of
  section 13.2, is assembled by MACRO on the guest, dumped, and compared
  module by module with poc's images, once at the end of the step and
  again whenever the encoder changes. It reaches far more of the
  generator than the fixtures do.
- **Coverage.** Every mnemonic in the opcode table and every form of
  section 13.2 occurs in what is compared, or a hand-written fixture
  adds it (`vax-encoder-forms`, its `.mar` assembled by MACRO the same
  way).

Differences that are legitimate disappear in the image, since both
sides are run to bytes: a forward difference poc computes and MACRO
leaves to the linker, an offset written as `STA_PB` or `STA_PW`, and
the way records are split. Anything left is a bug in one of the two
programs, and is fixed or listed here with the reason.

### 14.6 Pieces

Each piece leaves `make check` passing, the `.mar` output unchanged:

- **3a**: `tools/vax-image` and MACRO's images for the fixtures and the
  corpus, with what they show of the four things still unknown: `#0.0`;
  what `.ALIGN` fills with in `POC_CODE`; an integer literal in an `F`
  or `G` operand, if poc writes one; and `G^` of a symbol the same
  module defines. Each answer is written into this section.
- **3b**: `VaxOpcodes`, checked against Appendix D entry by entry and
  against every mnemonic the generator can compose.
- **3c**: the encoder for instructions and labels, `POC_CODE`, and
  `-emit-vax-image`, compared for the code sections.
- **3d**: directives and data, and the reals (`DecimalToDouble`'s new
  procedure), compared for every section. Done with 3c (section 14.9):
  the code's relocations name offsets in the data sections, so the code
  cannot be compared before the data is laid out.
- **3e**: the `expected-vax.image` files in every fixture's `test.sh`,
  the coverage fixture, and the corpus compared, every difference
  explained; the step's record in `PLAN.md`. Done (section 14.10).

### 14.7 What 3a found (2026-10-18)

`build/bin/vax-image` reads the objects of the step 1 sets, the 62
fixtures with an `expected-vax.mar` and the 35 modules of poc's own
source for the VAX, as `tools/vax-macro-image` brings them back from
MACRO on the guest: every record and TIR command in them is one it
knows, so the image of each is complete. The images of the nine
objects of section 1 that have MACRO's listing were checked against it:
every byte the listing shows (9,608) is the image's, and every field it
marks as relocated (965) is a relocation of the image to the same place,
or, a displacement or label difference in the same section, the value
the image computed. The fixture `vax-image-reader` keeps four of those
dumps and their images, and the second set's records also in the
counted form of section 10, so that `make check` tests the reader on
every host.

The four questions of section 14.6:

1. **`#0.0`** (section 12, question 2): immediate mode and zeros, four
   for an `F` operand, eight for a `G` one (`CVTFG #0.0, R0` is `99FD
   8F 00000000 50`). An integer `#0` in a real operand is the same,
   being converted to 0.0 first, never the short literal 0, which is 0.5.
   MACRO writes `#-0.0` as an `F` with only the sign bit set, a reserved
   operand on the VAX; poc never writes it.
2. **`.ALIGN`** is written only in `POC_DATA`, `POC_CONST` and
   `POC_ADDR`, never in `POC_CODE`, so what fills a gap in code does
   not arise: a gap is zeros.
3. **An integer literal in a real operand** is written by poc, 33 times,
   all in `vax-reals` (`MOVG #1, -8(FP)`, `MULG2 #10, R0`, `SUBF3 #3,
   ...`; none in the corpus),
   and MACRO converts it: `#10` is the short literal `22` (10.0),
   `#100` immediate mode and G 100.0 (`4079 0000 0000 0000`), `#-1` in
   `MOVF` F -1.0 (`C080 0000`), `#64` the short literal `38`, `#128`
   immediate (`4400 0000`). Section 14.3 says so.
4. **`G^` of a symbol the module defines**: never written, in the
   fixtures or the corpus. The encoder treats one as an error.

### 14.8 What 3b found (2026-10-18)

`src/back/vax/VaxOpcodes.Mod` holds 164 instructions: the 134 of
section 13.2 (every mnemonic in the 62 fixtures' and the 35 modules'
`.mar` is among them) and the rest of each family the generator
composes (`Op`, `Extension`, `CVT` and `MOVZ` with two data types), over
`B W L Q F G`. Each is checked three ways:

- **Against MACRO.** A `.mar` with every one of the 164, each read
  operand `#100` (too large for a short literal), each branch to its own
  label, assembles without a message, and decoding its listing with
  nothing but the table finds every opcode, every operand's specifier,
  every immediate's length and value (100, or 100.0 as an `F` or `G` for
  a real operand: `43C8 0000`, `4079 0000 0000 0000`), every branch
  displacement's length and every instruction's length as MACRO wrote
  them. That settles the opcodes where the OCR'd text of Appendix D is
  unreadable or missing (`D`/`0`, `8`/`B`/`S`; five lines lost): `CLRF`
  is `D4`, as Chapter 9's `CLR{L=F,Q=D=G,O=H}` says, not the `DF` the
  text shows.
- **Against Appendix D**, the OCR'd text: 158 of the 164 opcodes agree,
  24 of them only up to the confusions above; the other six are the
  lost lines and `CLRF`.
- **Against Chapter 9**, for the access types, which MACRO does not
  check: every operand's access (read, modify, write, address, field,
  branch) is the one in the instruction's summary line
  (`ADD{B,W,L}3 add1.rx, add2.rx, sum.wx`, `MOVC5 srclen.rw,
  srcaddr.ab, fill.rb, dstlen.rw, dstaddr.ab`, `B{cond} displ.bb`).
- **Against VSI's text of the manual**
  (`VSI/vsi-openvms-vax-macro-and-instruction-set-reference-manual.pdf`,
  much later than 5.5-2, but a born-digital PDF with no OCR errors;
  checked 2026-10-18): 162 of the 164 opcodes are its alphabetic table's
  exactly, and all 164 its numeric table's and Chapter 9's, and every
  access type is its Chapter 9's. The two others are typos in the
  alphabetic table D-1 itself, there in 5.4 and still in VSI's, not OCR
  errors: `CLRF` as `DF` and `MOVZBL` as `0A`, where table D-2,
  Chapter 9 and MACRO all give `D4` and `9A`. (Its Chapter 9 also prints
  `MOV{B,W,L,Q}` as `OV{B,W,L,Q}`, as the 5.4 text does.)
- **Against the architecture books** (`DEC_VAX_Architecture_Handbook.pdf`,
  1986, EB-26115-46, Appendices B and C; and
  `EY-3459E-DP_VAX_Architecture_Reference_Manual_1987.pdf`, Appendix A,
  read by its binary column, which OCR leaves whole; checked
  2026-10-18): all 164 opcodes agree, and both give `CLRF` as `D4` and
  `MOVZBL` as `9A`, so D-1's typos are the MACRO manual's alone. Every
  other difference in their text was OCR, checked on the page images.
  (The Handbook prints `CASEB`'s row as `CASE`, "BCase byte".) The
  architecture books are the authority for the encoding, which no VMS
  release changes; the MACRO manual is the authority for what MACRO
  accepts and which forms it picks, which the architecture books do
  not describe.

### 14.9 What 3c found (2026-10-18)

`src/back/vax/VaxEncoder.Mod` encodes a module's lines into a `VaxImage`,
the directives, data and reals included (3d's part, section 14.6), and
`poc -emit-vax-image` writes it, as `<Module>.image`, beside the `.mar`
that `-emit-macro32` writes (`VaxToolchainDriver.WriteImage`).
`DecimalToDouble.RoundedParts` gives the encoder a numeral rounded to 24
or 53 bits as an integer and an exponent, from which it builds the `F`
or `G` bits; `Rounded`, which the front end uses, is now built on it.

Every image is MACRO's, byte for byte, with no difference to explain:
the 62 fixtures with an `expected-vax.mar` (`vax-reals`, with its real
literals, integer literals in real operands and 271 relocations,
included), and all 35 modules of poc's own source for the VAX (32 from
the corpus of section 14.7, and `BuildInfo`, `Libraries` and `Poc`,
whose source carries the build's commit, assembled again by MACRO from
the same tree). Encoding the 35 modules takes about a second here.

### 14.10 What 3e found (2026-10-18)

Every VAX fixture with an `expected-vax.mar` now has an
`expected-vax.image`, and each of its imports an
`expected-vax-<Import>.image`, 101 images in all, each made by MACRO on
the guest from the committed `.mar` (`tools/vax-macro-image`).
`vax_mar` (`test/vaxfixture.sh`) runs `poc -emit-vax-image`, which writes
the `.mar` as before and each module's image beside it, and compares
every image with its expected one, with no guest needed, so `make check`
tests the encoder on every host; `vax-cardinal` and `vax-for-loop-end`,
which build with `-build`, run `-emit-vax-image` for their main module
and compare it the same way. An expected image changed by one byte makes
its fixture fail.

The fixtures reach 130 of the opcode table's 164 instructions and most of
section 13.2's forms, but not every displacement size in every mode,
nor quadword or narrow hexadecimal immediates. The coverage fixture
`vax-encoder-forms` adds the rest: `EncoderForms.Mod`, built with poc
from `src/back/vax` and `src/front`, makes the lines of a module with
every instruction of the table, each with an operand of each of its
operand types chosen in turn from the forms that type allows (25
specifier forms, literals of each kind for read operands, and branches
back and forward), then the displacements and literals at the edges of
each size, reals and integers in real operands for F and G, references
backward over a byte, a word and a longword, forward, to another
section, external, `G^` and `L^`, with offsets and index registers,
branches and a CASE table, a private procedure, and every directive and
kind of item. It writes them as MACRO-32 and as poc's image; the
fixture compares the first with its `expected-vax.mar` and the second
with the image of MACRO's object for it. With the fixtures, every
mnemonic of the table, every form of section 13.2 and every directive is
compared.

It found two choices of MACRO's that no fixture or corpus module had
reached, and the encoder now makes both:

- **`0(Rn)` is `(Rn)`.** MACRO assembles a displacement of 0 as register
  deferred, one byte shorter, indexed too (`0(R3)[R7]` is `(R3)[R7]`),
  but keeps the byte displacement of `@0(Rn)`, which has no shorter
  form.
- **A quadword immediate is a longword, zero-extended.** MACRO's
  expressions are 32 bits: `MOVQ #-77, R0` stores `FFFFFFB3 00000000`,
  not -77 sign-extended. poc writes no negative literal in a quadword
  operand (`ASHQ`'s count is a byte), so no program poc made was wrong.

And one the encoder did not report: a literal or a `.BYTE` or `.WORD`
item too wide for its operand or directive is MACRO's "data truncation"
warning, which `tools/vax-assemble` counts as a failure; the encoder now
refuses one with an error (`the VAX encoder found a literal too wide for
its operand`), where it stored the low bytes. Its messages also lost a
stray space before the ": " that `Diagnostics.ErrorAbout` adds.

The corpus, poc's own source for the VAX, is now 39 modules
(`VaxInstructions`, `VaxImage`, `VaxOpcodes` and `VaxEncoder` have joined
the 35 of section 14.7): MACRO assembled all 39 from the tree of this step, and
all 39 images are poc's, byte for byte. No difference is left to explain.

## 15. Step 4: the object writer (decided 2026-10-18)

### 15.1 What it takes and what it gives

`VaxObjectWriter` takes the `VaxImage.Module` the encoder makes and
writes the module's object, its records in the order of section 3:
MHD, LNM and SRC; the GSD; each section's TIR; the EOM. It reads
nothing else: everything a record needs is in the image (sections with
their flags, sizes, bytes and relocations; symbols, entry masks and
references; the transfer address), and the image is already MACRO's,
byte for byte (section 14.10). No TBT or DBG records yet: they are
step 5's, and until step 6 makes direct objects the default, MACRO's
objects, with their traceback, are still the ones programs are built
from.

### 15.2 The records

- **Headers** (section 4): MHD with `MHD$W_RECSIZ` 512, the image's
  name and ident, the creation time from `Platform.GetClock` (in every
  `Platform` poc is built with: voc's, `rtl/llvm`'s and `rtl/vax`'s) as
  `dd-mmm-yyyy hh:mm`, or, when the environment variable
  `SOURCE_DATE_EPOCH` is set, that time (seconds since 1970, UTC), as
  reproducible builds elsewhere take it, and 17 spaces for the last patch; LNM
  `Peaseblossom poc <version>` (`Version.Mod`); SRC the source file's
  name as given to poc.
- **GSD** (section 5): one PSC per section, in the image's order, which
  is MACRO's (`.  ABS  .` first); then a SYM definition for each symbol
  that is not an entry point (REL unless absolute), an EPM for each
  entry point with its mask, and a SYM reference for each external. A
  record is closed before a subrecord would take it past 512 bytes.
- **TIR** (section 6), one section at a time, after `STA_Px` section, 0
  and `CTL_SETRB`: the bytes as Store Immediates of up to 128; a run of
  16 zeros or more skipped with `CTL_AUGRB` (shorter runs stored), so
  that `.BLKx` space stays demand-zero; and at each relocation, the
  commands of section 6.1 for its kind: for `LD` and `LW`, the target
  (`STA_GBL`, or `STA_PB`/`PW`/`PL` with the addend folded into the
  offset) and, for a global with an addend, `STA_LW` and `OPR_ADD`,
  then `STO_LD` or `STO_LW`; for `PIDR`, the same and `STO_PIDR`; for
  `PICR`, the same and `STO_PICR`, which writes the specifier byte
  itself, so the Store Immediate before it stops short of that byte.
  Each relocation's commands stay in one record, and a record is closed
  before it would pass 512 bytes. The entry mask is in the section's
  bytes already, so it is a Store Immediate (section 5.3).
- **EOM** (section 8): severity 0, and the transfer address's section
  and offset in the main module.

What poc writes differs from MACRO's object only as section 9 allows,
so the image read back from poc's object must equal MACRO's image.

### 15.3 Where the records go (section 10)

The writer hands each record to `ObjectRecords` (`Open(name)`,
`Put(bytes, length)`, `Close`), which has two implementations, chosen
by the import path as `src/driver/no-llvm` chooses its modules:

- `src/back/vax/host/ObjectRecords.Mod`, for poc built for Linux and
  the BSDs (and Stage 0 under voc): through `Files`, the counted form
  of section 10, a 2-byte little-endian count, the bytes, and a pad
  byte when the count is odd.
- `src/back/vax/vms/ObjectRecords.Mod`, for poc built for VMS: through
  a new runtime module `rtl/vax/RecordFiles.Mod`, `Create(name, maximum)`,
  `Put(VAR bytes, length)`, `Close`, over routines in `PocRtl.mar` that
  create a sequential file of variable-length records with no record
  attributes and `$PUT` each record. It is VAX-only (no `rtl/llvm`
  twin) and is the only new interface programs can see.

Its file is `<module>.obj` on Linux and the BSDs, `<MODULE>.OBJ` on
VMS.

**On the guest**, a counted file sent by FTP in binary mode becomes
fixed 512-byte records, padded with zeros. `tools/objconvert/
ObjectConvert.Mod`, a VMS program built with poc, reads it with `Files`
as bytes, record by record until a count of 0 or the end, and writes
`<MODULE>.OBJ` with `RecordFiles`. `tools/vax-ftp.tcl` gains binary
transfers (`TYPE I`); `tools/vax-do` and `tools/vax-run` send each
`.obj` that way and run the converter on it before the procedure. The
converter is built on the guest, through MACRO like any program today,
into each account's `[.BIN]`, the first time a run needs it and again
when its module key changes.

### 15.4 Testing

- **Every host, every fixture.** A testing command,
  `poc -emit-vax-object <file>` (like `-emit-vax-image`; step 6 adds
  the real mode), writes the `.mar` and each module's object in the
  counted form. `vax_mar` reads each object back with `build/bin/
  vax-image` (whose reader is its own, not the writer's: section 14.5)
  and compares the image with `expected-vax.image`, MACRO's, in place
  of the encoder's printed image; so every fixture tests the encoder and
  the writer together, with no guest. `make test` and `test-stage1`
  build `vax-image` first. `-emit-vax-image` stays, for finding which of
  the two a difference is in.
- **The records themselves**, which the image does not show (their
  order, their split at 512 bytes, the headers): a fixture,
  `vax-object-records`, prints a few objects' records as `vax-image`
  sees them (`vax-image -records`), compared with what is expected.
- **On the guest** (where it can be used, as `vax_mar` assembles today):
  each fixture's objects, converted, pass `ANALYZE/OBJECT` with no
  errors or warnings.
- **`LINK` and run.** `vax-cardinal` and `vax-for-loop-end`, which build
  and run a whole program on the guest (twelve and six modules with the
  runtime's), also build it from poc's objects, with `PocRtl` from
  MACRO, and their output must be the same. Phase 17's libraries and
  shareable images from direct objects are step 6's test, as `PLAN.md`
  says; their psect attributes are MACRO's already (the images agree).

### 15.5 Pieces

Each leaves `make check` passing:

- **4a**: `VaxObjectWriter`, the host `ObjectRecords`,
  `-emit-vax-object`, and `vax_mar` comparing the object's image, on
  every host; Stage 0, Stage 1 and `vax-v1` given the host or VMS
  directory.
- **4b**: `vax-image -records` and the fixture `vax-object-records`.
- **4c**: `RecordFiles` and its `PocRtl` routines, the VMS
  `ObjectRecords`, `ObjectConvert`, binary FTP and the conversion in
  `vax-do` and `vax-run`; `ANALYZE/OBJECT` of every fixture's objects.
- **4d**: the two programs linked from poc's objects and run; what was
  found written here (15.6 on), and the step's record in `PLAN.md`.

### 15.6 Decided (the user, 2026-10-18)

1. The names as proposed: `VaxObjectWriter`, `ObjectRecords` in
   `src/back/vax/host` and `src/back/vax/vms`, `RecordFiles` in
   `rtl/vax`, `ObjectConvert`, and the testing command
   `-emit-vax-object`.
2. The creation time is the clock's, or `SOURCE_DATE_EPOCH`'s when it is
   set (section 15.2); step 7's comparison skips it otherwise.
3. Zeros are skipped from 16 in a row, as proposed.

### 15.7 What 4a found (2026-10-18)

`src/back/vax/VaxObjectWriter.Mod` writes a module's object from its
image, and `poc -emit-vax-object` writes it, as `<Module>.obj`, beside
the `.mar` (`VaxToolchainDriver.WriteObject`), through
`src/back/vax/host/ObjectRecords.Mod`. `VaxImage` exports a way to walk
its sections, relocations, symbols and references for it.

`vax_mar` now runs `-emit-vax-object` and reads each object back with
`build/bin/vax-image`, which `make test` and `test-stage1` build first,
into the `<Module>.image` it compares with the expected one, so the
fixtures' results read as before. Every fixture's object gives MACRO's
image, the 101 of section 14.10 and `vax-encoder-forms`'s; so do all 41
modules of poc's own source for the VAX (`ObjectRecords` and
`VaxObjectWriter` have joined them), 2,714 records, the longest 512
bytes, compared with the encoder's own image of each. `SOURCE_DATE_EPOCH`
gives the dates it should, 29 February 2000 included, and a value that
is not a number is ignored for the clock's.

One change from section 15.5: the VMS build of poc compiles
`VaxToolchainDriver`, so it needs an `ObjectRecords` now, not in 4c.
`src/back/vax/vms/ObjectRecords.Mod` has the interface, and until 4c
the host's body; `tools/bootstrap/vax-v1`, `vax-stages`, `make-vax-kit`,
`check-vax-kit`, the kit's `README.TXT`, `doc/vax-vms-guide.md` and the
fixture `vax-poc` name its directory already, so 4c changes only the
file. `check-strict` checks it as it does `src/driver/no-llvm`.

### 15.8 What 4b found (2026-10-18)

`vax-image -records <object>` prints an object's records, a line for
each (its type and length), then one for each header field, GSD
subrecord, TIR command and EOM field, which the image does not show:
store immediates by their length, relocations by their commands. The
fixture `vax-object-records` prints so the objects poc writes for
`VaxEmpty`, `VaxVarRecords` and `VaxMethods` (the last 13 TIR records,
the longest 511 bytes) under a fixed `SOURCE_DATE_EPOCH`, with poc's
version left out of the `LNM` record, and compares them with
`expected-<Module>.records`, which were checked by eye against sections
6 and 15.2. `EncoderForms` in `vax-encoder-forms` also writes its object,
`forms.obj`, which `vax-image` reads back into `forms-object.image`,
compared with MACRO's `expected-vax.image`: that object has the commands
the fixtures' modules do not reach, `STO_LW`, `OPR_ADD`, `STA_SB` and
`STA_PL` among them. Nothing poc wrote needed changing.
