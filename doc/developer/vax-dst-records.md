# The VAX debugger's DST records, for poc (Phase 18 step 5)

The records of the debug symbol table (DST) that VAX/VMS compilers write
in their TBT and DBG object records, as far as poc needs them, digested
from the debugger's own definition file on 2026-10-18 for
`doc/developer/vax-object-language.md`, section 16, which says what poc
writes and what the guest's compilers and debugger showed beyond this.
Where they differ, section 16 and the guest win: this is VMS 4.0's file.

Source: `DSTRECRDS.REQ` V04-000 (16-SEP-1984, VMS V4.0 listing),
OCR text `~/Reference/Computer/OS/VMS/009__DSTRECRDS.REQ__bw-ocr.text`
(cited below as "L\<n\>", OCR line numbers). The PDF beside it was read
wherever the OCR was doubtful; **PDF page = listing page + 2** (listing
"Page 25" is PDF page 27). Values marked **[PDF]** were checked against
the scan. The VMS 5.5-2 guest's `STARLET` `$DSTDEF` (1993, in the repo as
`rtl/vax/vms/DSTDEF.Mod`) has only the stack-machine opcodes 0-23, and
they match this file's (section 5.6), so that part at least did not change
between 4.0 and 5.5-2. Descriptor classes and the array descriptor layout
come from `rtl/vax/vms/DSCDEF.Mod` (STARLET 1993), not from this file.

Conventions: offsets are bytes from the start of the DST record (the
length byte is offset 0). "L" = longword, "W" = word, "B" = byte, all
little-endian. BLISS field `[o, B_]` = byte at o, `[o, L_]` = longword
at o, `[o, V_(p,s)]` = bit field at bit p, s bits wide, `[o, A_]` = the
address of offset o (a variable-length part starts there).

---

## 1. The DST record header, and nesting

### 1.1 Header (L907-929)

| Off | Size | Field | Meaning |
|---|---|---|---|
| 0 | B | `DST$B_LENGTH` | length of the record **not counting this byte** (so total size = LENGTH + 1; max 255) |
| 1 | B | `DST$B_TYPE` | record type |
| 2 | var | — | the rest. `DST$A_NEXT` = [1, A_]: the next record starts at offset 1 + LENGTH |

`DST$B_TYPE` (L932-948): a value in `DSC$K_DTYPE_LOWEST..HIGHEST` (1..37)
means a **Standard Data record** (or variant) whose type *is* that VAX
standard type; a value in `DST$K_LOWEST..DST$K_HIGHEST` (153..191), or
`DST$K_BLI` (0), names a record format. DEBUG ignores any other type code
(38..152, 192..255).

### 1.2 Record type codes, all (L1042-1110) [PDF p.24 for 163-191]

| Dec | Hex | Name | Record | poc? |
|---|---|---|---|---|
| 0 | 00 | `DST$K_BLI` | BLISS special cases | no |
| 153 | 99 | `DST$K_VERSION` | Version Number | optional |
| 154 | 9A | `DST$K_COBOLGBL` | COBOL Global Attribute | no |
| 155 | 9B | `DST$K_SOURCE` | Source File Correlation | **yes** |
| 156 | 9C | `DST$K_STATLINK` | Static Link | probably not |
| 157 | 9D | `DST$K_VARVAL` | Variant Value | no |
| 158 | 9E | `DST$K_BOOL` | Standard Data record of type BOOLEAN (1 byte, low bit) | **yes** |
| 159 | 9F | `DST$K_EXTRNXT` | External-Is-Next (obsolete) | no |
| 160 | A0 | `DST$K_GLOBNXT` | Global-Is-Next (obsolete) | no |
| 161 | A1 | `DSC$K_DTYPE_UBS` | DEBUG internal (obsolete) | no |
| 162 | A2 | `DST$K_PROLOG` | Prolog | **yes** |
| 163 | A3 | `DST$K_SEPTYP` | Separate Type Specification | **yes** |
| 164 | A4 | `DST$K_ENUMELT` | Enumeration Type Element | no |
| 165 | A5 | `DST$K_ENUMBEG` | Enumeration Type Begin | no |
| 166 | A6 | `DST$K_ENUMEND` | Enumeration Type End | no |
| 167 | A7 | `DST$K_VARBEG` | Variant Set Begin | no |
| 168 | A8 | `DST$K_VAREND` | Variant Set End | no |
| 169 | A9 | `DST$K_OVERLOAD` | Overloaded Symbol (Ada; not supported by DEBUG V4.0) | no |
| 170 | AA | `DST$K_DEF_LNUM` | Definition Line Number (not supported by DEBUG V4.0) | no |
| 171 | AB | `DST$K_RECBEG` | Record Begin | **yes** |
| 172 | AC | `DST$K_RECEND` | Record End | **yes** |
| 173 | AD | `DST$K_CONTIN` | Continuation | if a record > 255 bytes |
| 174 | AE | `DST$K_VALSPEC` | Value Specification (ignored by DEBUG) | no |
| 175 | AF | `DST$K_TYPSPEC` | Type Specification | **yes** |
| 176 | B0 | `DST$K_BLKBEG` | Block Begin | maybe |
| 177 | B1 | `DST$K_BLKEND` | Block End | maybe |
| 178 | B2 | `DST$K_COB_HACK` | COBOL Hack (obsolete) | no |
| 179, 180 | B3, B4 | — | reserved to DEBUG | no |
| 181 | B5 | `DST$K_ENTRY` | Entry Point (secondary entry) | no |
| 182 | B6 | `DST$K_LINE_NUM_REL_R11` | Threaded-code PC correlation (obsolete) | no |
| 183 | B7 | `DST$K_BLIFLD` | BLISS Field | no |
| 184 | B8 | `DST$K_PSECT` | PSECT | MACRO only (DEBUG ignores it for other languages) |
| 185 | B9 | `DST$K_LINE_NUM` | Line Number PC-Correlation | **yes** |
| 186 | BA | `DST$K_LBLORLIT` | Label-or-Literal (MACRO) | no |
| 187 | BB | `DST$K_LABEL` | Label | optional |
| 188 | BC | `DST$K_MODBEG` | Module Begin | **yes** |
| 189 | BD | `DST$K_MODEND` | Module End | **yes** |
| 190 | BE | `DST$K_RTNBEG` | Routine Begin | **yes** |
| 191 | BF | `DST$K_RTNEND` | Routine End | **yes** |

`DST$K_LOWEST` = 153, `DST$K_HIGHEST` = 191.

### 1.3 Nesting (L468-620, L1119-1133, L1283-1351, L1423-1453)

- The DST is one contiguous sequence of records; each module's part is
  bracketed by Module Begin ... Module End, and only **one** pair per
  object module (the linker tells DEBUG only of the first Module Begin).
- Scopes nest by Begin/End pairs: Routine Begin/End (a CALLS/CALLG or
  JSB/BSB-entered routine) and Block Begin/End (a scope entered by
  falling or jumping in, no entry point) nest freely inside each other to
  any depth, properly bracketed. Every record between a Begin and its End
  is a symbol of that scope (or of a nested one). Nested procedures are
  nested Routine Begin/End pairs, inside the outer routine's pair.
- A data record's scope is the innermost enclosing Routine/Block (or the
  module). Up-level references: DEBUG finds the enclosing routine's frame
  itself (by walking the call stack to the most recent invocation of the
  outer routine), unless a Static Link record says otherwise (L4932-4981:
  "only makes a difference for recursive routines that pass routines as
  parameters"). So poc describes each variable once, in the routine that
  declares it; the hidden pointer parameters need no DST description.
- Record types are bracketed by Record Begin ... Record End (L3185-3313);
  a Separate Type Specification record must be **immediately** followed
  by the record that gives its type (Type Spec, Record Begin, or Enum
  Begin; only Continuation records may intervene, L1814-1823).
- Line Number and Source File Correlation records ignore nesting: they
  may appear anywhere between the module's Begin and End, e.g. all after
  the last Routine End (L775-783, L4001-4017).
- Example sequence (L1300-1341):

```
Module Begin M
  data records for module-level variables
  Routine Begin R1
    data records for R1's locals and parameters
    Routine Begin R2 ... Routine End
    Block Begin B1 ... Block End
  Routine End (R1)
  ... line number / source records anywhere ...
Module End
```

---

## 2. Module Begin and Module End

### 2.1 Module Begin, `DST$K_MODBEG` = 188 = 0xBC (L1137-1171) [PDF p.26]

| Off | Size | Field | Value |
|---|---|---|---|
| 0 | B | `DST$B_LENGTH` | 7 + n |
| 1 | B | `DST$B_TYPE` | 0xBC |
| 2 | B | `DST$B_MODBEG_UNUSED` | 0 (must be zero) |
| 3 | L | `DST$L_MODBEG_LANGUAGE` | language code (below) |
| 7 | B | `DST$B_MODBEG_NAME` | n, count of the counted-ASCII name |
| 8 | n | — | module name |

`DST$K_MODBEG_SIZE` = 8 (fixed part). This matches MACRO's TBT record
(vax-object-language.md section 7: flags 0, language 0, counted name).
There are **no version fields** in Module Begin; the compiler version is a
separate Version Number record (section 7.3).

### 2.2 Language codes (L1175-1262) [PDF p.27]

| Value | `DST$K_` | (`DBG$K_` synonym, same value) |
|---|---|---|
| 0 | `MIN_LANGUAGE`, `MACRO` | Macro |
| 1 | `FORTRAN` | |
| 2 | `BLISS` | |
| 3 | `COBOL` | |
| 4 | `BASIC` | |
| 5 | `PLI` | |
| 6 | `PASCAL` | |
| 7 | `C` | |
| 8 | `RPG` | |
| 9 | `ADA` | |
| **10** | `UNKNOWN` | Language unknown |
| 10 | `MAX_LANGUAGE` | largest code |

**`DST$K_UNKNOWN` is 10, not 16.** The OCR reads "16" (it reads every
"10" in this file as "16"); the scan clearly shows 10, and it equals
`DST$K_MAX_LANGUAGE`. `vax-object-language.md` section 12 question 3
copied the OCR's 16; it is corrected there.

Notes from the text (L1236-1262): DEBUG treats any out-of-range code as
UNKNOWN; UNKNOWN gives language-independent functionality plus "vanilla"
expressions (identifiers of A-Z 0-9 $ _, subscripts with () or [],
`A.B.C` component selection, most simple operators); it is "intended as
an escape for compilers which do not yet have true DEBUG support" and is
"not officially supported". DEBUG reads the code as a **byte** (codes
above 255 are truncated). VMS 5.5-2's DEBUG certainly knows languages
added after 4.0 (DIBOL and SCAN are in V5 `SET LANGUAGE`), so codes 11+
exist there but are not in this file; from memory only (unverified):
11 SCAN, 12 DIBOL; later releases also MODULA 13. Do not rely on them.

### 2.3 Module End, `DST$K_MODEND` = 189 = 0xBD (L1267-1280)

`01 BD`: LENGTH = 1, TYPE = 0xBD. `DST$K_MODEND_SIZE` = 2. Must be the
module's last DST record.

---

## 3. Routines and blocks; addresses in a DBG stream

### 3.1 Routine Begin, `DST$K_RTNBEG` = 190 = 0xBE (L1354-1396)

| Off | Size | Field | Value |
|---|---|---|---|
| 0 | B | `DST$B_LENGTH` | 7 + n |
| 1 | B | `DST$B_TYPE` | 0xBE |
| 2 | B | `DST$V_RTNBEG_UNUSED` = bits 0-6 (0); `DST$V_RTNBEG_NO_CALL` = bit 7 | 0 for a CALLS/CALLG routine; 0x80 for a JSB/BSB routine |
| 3 | L | `DST$L_RTNBEG_ADDRESS` | start address = entry point (relocated) |
| 7 | B | `DST$B_RTNBEG_NAME` | n |
| 8 | n | — | routine name |

`DST$K_RTNBEG_SIZE` = 8. "It is assumed that the start address is also the
entry point" (L1349); for a CALLS routine that is the entry mask word.

### 3.2 Routine End, `DST$K_RTNEND` = 191 = 0xBF (L1401-1420) [PDF p.32]

| Off | Size | Field | Value |
|---|---|---|---|
| 0 | B | `DST$B_LENGTH` | 6 |
| 1 | B | `DST$B_TYPE` | 0xBF |
| 2 | B | unused | 0 |
| 3 | L | `DST$L_RTNEND_SIZE` | routine length in bytes (a plain constant, no relocation) |

**Mandatory for every language except MACRO**, where it must be omitted
(L1359-1363, L1404-1406). So poc (not MACRO) must write a Routine End for
every Routine Begin, which MACRO's own TBT records do not have.

### 3.3 Block Begin `DST$K_BLKBEG` = 176 = 0xB0, Block End `DST$K_BLKEND` = 177 = 0xB1 (L1456-1523)

Block Begin: 0 LENGTH (7+n), 1 TYPE 0xB0, 2 `DST$B_BLKBEG_UNUSED` (0),
3 L `DST$L_BLKBEG_ADDRESS` (relocated), 7 B `DST$B_BLKBEG_NAME` count
(0 for an unnamed block), 8 name.

Block End: 0 LENGTH = 6, 1 TYPE 0xB1, 2 unused 0, 3 L `DST$L_BLKEND_SIZE`
(bytes). Oberon has no inner blocks; poc needs them only if it wants a
scope narrower than a routine (it does not).

### 3.4 Prolog, `DST$K_PROLOG` = 162 = 0xA2 (L4984-5013)

| Off | Size | Field | Value |
|---|---|---|---|
| 0 | B | `DST$B_LENGTH` | 5 |
| 1 | B | `DST$B_TYPE` | 0xA2 |
| 2 | L | `DST$L_PROLOG_BKPT_ADDR` | address where routine breakpoints go (relocated) |

Note: **no unused byte**; the address is at offset 2. Optional. Without
it DEBUG puts `SET BREAK routine` at the routine's start address. With it,
at the first instruction after the prolog, so that locals and parameters
are valid when the break is taken. It belongs to the nearest preceding
Routine Begin (or Entry Point) record not counting nested routines;
"placing it immediately after the Routine Begin ... is good practice".
For poc: after the entry mask, `SUBL2 #n,SP`, the zeroing of locals, and
the copying of value open arrays.

### 3.5 How an address gets into a DST record (DBG/TBT TIR streams)

The DST format only says the field holds an address; the linker fills it
in. The DBG (04) and TBT (05) records are TIR command streams run against
the linker's **separate DST location counter** (Linker manual 5.0, 7.7:
"initialized as if the DST is the highest addressed part of the program
region"; 7.8: TBT is processed identically and may be mixed with DBG).
What MACRO does (vax-object-language.md section 7, observed): the fixed
bytes as a Store Immediate; each address as `STA_PB`/`STA_PW`/`STA_PL`
(psect index, offset) [+ `STA_UB` n, `OPR_ADD`] then `STO_PIDR`. poc
should write the same: every relocated longword in a DST record
(Routine Begin, Block Begin, Prolog, Label, a static data address, a
`DST$K_SET_ABS_PC` operand, an `A0`/`POINTER` in an embedded descriptor)
is `STA_Px psect, offset ; STO_PIDR`. Sizes (Routine End, Block End) and
FP/AP offsets are plain bytes in the Store Immediate.

For **DST pointers** (offsets into the DST: Indirect Type Spec, Novel
Length parent, Variant tag pointer) the linker has three commands valid
only in DBG and TBT records (Linker manual 7.4, codes 82-84):

| Code | Command | Effect |
|---|---|---|
| 82 | `TIR$C_CTL_DFLOC` | pop an index; save the current (DST) location counter under it |
| 83 | `TIR$C_CTL_STLOC` | pop an index; set the location counter to the value saved under it |
| 84 | `TIR$C_CTL_STKDL` | pop an index; push the location counter saved under it |

The intended use: `STA_xx index; CTL_DFLOC` just before writing the
target record (a Record Begin or Type Spec), and `STA_xx index;
CTL_STKDL; STO_LW` (or `STO_PIDR`) where a pointer to it is stored; a
forward pointer can be stored by leaving a hole and coming back with
`CTL_STLOC`. **Doubt**: DSTRECRDS says a DST pointer is "the byte offset
relative to the start of the whole DST" (L2620-2624, L3045-3048, L3377-3379),
while the linker's saved location counter is a virtual address of the
DST "as if" mapped at the top of the image. Either the linker's DST
location counter starts at 0 for the DST, or DEBUG subtracts the DST's
base, or the compiler must subtract something; this file does not say.
**To settle by dumping a guest compiler's DBG records** for a program
with a named record type used by two variables (VAX C `struct`, or Ada),
and seeing which TIR commands build the `DST$L_TS_IND_PTR` field.

---

## 4. Line numbers and source files

### 4.1 Line Number PC-Correlation record, `DST$K_LINE_NUM` = 185 = 0xB9 (L3982-4431)

| Off | Size | Field |
|---|---|---|
| 0 | B | `DST$B_LENGTH` |
| 1 | B | `DST$B_TYPE` = 0xB9 |
| 2 | var | `DST$A_LINE_NUM_DATA`: one or more PC-correlation commands |

Rules (L4001-4026): all these records in a module form **one command
stream**, in order; they may be split over as many records as needed,
but **no command may be split across records**, and Continuation records
may **not** be used for them. They may sit anywhere inside the module.

Each command is a command byte, optionally followed by an unsigned byte,
unsigned word, or longword parameter (L4034-4110). Codes [PDF p.103]:

| Code | Name | Param | Semantics |
|---|---|---|---|
| -128..0 | Delta-PC (`DST$K_DELTA_PC_LOW` = -128, `_HIGH` = 0) | none | LINE += INCR (or STMT += 1 in statement mode); PC += -code; MARK := open. **0 is legal**: a line at the current PC |
| 1 | `DST$K_DELTA_PC_W` | W | as Delta-PC, PC += word |
| 17 | `DST$K_DELTA_PC_L` | L | as Delta-PC, PC += longword |
| 2 | `DST$K_INCR_LINUM` | B | LINE += byte (STMT := 1 if statement mode) |
| 3 | `DST$K_INCR_LINUM_W` | W | LINE += word |
| 18 | `DST$K_INCR_LINUM_L` | L | LINE += longword |
| 4 | `DST$K_SET_LINUM_INCR` | B | INCR := byte |
| 5 | `DST$K_SET_LINUM_INCR_W` | W | INCR := word |
| 6 | `DST$K_RESET_LINUM_INCR` | none | INCR := 1 |
| 7 | `DST$K_BEG_STMT_MODE` | none | statement mode on, STMT := 1 (only while a line is open) |
| 8 | `DST$K_END_STMT_MODE` | none | statement mode off, STMT := 1 |
| 13 | `DST$K_SET_STMTNUM` | W (see doubt) | STMT := value |
| 19 | `DST$K_SET_LINUM_B` | B | LINE := byte |
| 9 | `DST$K_SET_LINUM` | W | LINE := word |
| 20 | `DST$K_SET_LINUM_L` | L | LINE := longword |
| 10 | `DST$K_SET_PC` | B | PC := START_PC + byte (only while line closed) |
| 11 | `DST$K_SET_PC_W` | W | PC := START_PC + word (line closed) |
| 12 | `DST$K_SET_PC_L` | L | PC := START_PC + longword (line closed) |
| 16 | `DST$K_SET_ABS_PC` | L | PC := absolute address (line closed; needs relocation) |
| 14 | `DST$K_TERM` | B | PC += byte (the length of the last line); MARK := closed |
| 15 | `DST$K_TERM_W` | W | same, word |
| 21 | `DST$K_TERM_L` | L | same, longword |

`DST$K_PCCOR_LOW` = -128, `DST$K_PCCOR_HIGH` = 21. Codes 1-21 other than
those listed: none unused (1..21 are all assigned).

State and initial values (L4116-4143): CURRENT_LINE = 0, CURRENT_STMT = 1,
CURRENT_INCR = 1, statement mode off, **START_PC = start address of the
lowest-address routine in the module**, CURRENT_PC = START_PC, MARK =
closed. Note the Delta-PC order: line and PC are both advanced *before*
the correlation is made, so "Delta-PC d" means "the next line starts d
bytes after the previous line's start".

**A sequence that defines lines L1 < L2 < ... at PCs p1 < p2 < ...
for one routine** (one TERM per routine, then SET_PC for the next):

```
SET_PC_W   (p1 - START_PC)      ; while closed (or SET_ABS_PC + reloc)
SET_LINUM  (L1 - 1)             ; LINE := L1-1 (word; _B or _L by size)
Delta-PC   0                    ; LINE := L1 at PC p1, line open
SET_LINUM  (L2 - 1)             ; or INCR_LINUM (L2-L1-1), or nothing if L2 = L1+1
Delta-PC   -(p2 - p1)           ; byte form if <= 128, else DELTA_PC_W/_L
...
TERM       (end of routine - p_last)   ; closes
```

A line whose code is not contiguous, or line numbers that go back
(a `WHILE`'s test placed after the body, `FOR` limits, `REPEAT`), are
expressible with `SET_LINUM` before each Delta-PC; whether DEBUG then
puts `SET BREAK %LINE n` on the first range only, and how `STEP` treats
a line seen twice, is not said here: to test on the guest.

What the debugger needs:
- `SET BREAK %LINE n`, `STEP` (by line), and the line number in a
  breakpoint/step report and in a traceback: the PC-correlation records,
  plus Routine Begin/End so the PCs fall in a known routine. Without the
  `/DEBUG` symbols (a TBT-only link), traceback still prints line numbers
  from these records.
- `TYPE n`, the source shown at a breakpoint, `SET MODE SCREEN`'s source
  display: additionally the Source File Correlation records (4.2), which
  map listing line numbers to records of a source file.

### 4.2 Source File Correlation record, `DST$K_SOURCE` = 155 = 0x9B (L4437-4898)

| Off | Size | Field |
|---|---|---|
| 0 | B | `DST$B_LENGTH` |
| 1 | B | `DST$B_TYPE` = 0x9B |
| 2 | var | `DST$A_SRC_FIRST_CMD`: source file correlation commands |

May be spread over many records, processed in order (L4463-4467). State:
LINE_NUM (initially **1**), SRC_FILE, SRC_REC (initially undefined); one
action DEFINE(LINE_NUM, SRC_FILE, SRC_REC). Lines must be DEFINEd in
increasing order of line number (L4502-4505). Form-feed-only records are
not counted as source records unless `DST$K_SRC_FORMFEED` is given first.

Command codes [PDF p.113]:

| Code | Name | Param | Semantics |
|---|---|---|---|
| 1 | `DST$K_SRC_DECLFILE` | variable (below) | declare a source file and its file ID |
| 2 | `DST$K_SRC_SETFILE` | W file ID | SRC_FILE := id; SRC_REC := that file's current record |
| 3 | `DST$K_SRC_SETREC_L` | L | SRC_REC := value |
| 4 | `DST$K_SRC_SETREC_W` | W | SRC_REC := value |
| 5 | `DST$K_SRC_SETLNUM_L` | L | LINE_NUM := value |
| 6 | `DST$K_SRC_SETLNUM_W` | W | LINE_NUM := value |
| 7 | `DST$K_SRC_INCRLNUM_B` | B | LINE_NUM += value |
| 8, 9 | — | | unused |
| 10 | `DST$K_SRC_DEFLINES_W` | W count | repeat count times: DEFINE; LINE_NUM += 1; SRC_REC += 1 |
| 11 | `DST$K_SRC_DEFLINES_B` | B count | same, byte count |
| 12..15 | — | | unused |
| 16 | `DST$K_SRC_FORMFEED` | none | count form-feed records as source records (put it first) |

`DST$K_SRC_MIN_CMD` = 1, `DST$K_SRC_MAX_CMD` = 16. Parameter fields:
`DST$L_SRC_UNSLONG` [1, L_], `DST$W_SRC_UNSWORD` [1, W_],
`DST$B_SRC_UNSBYTE` [1, B_] (the OCR's "7" is wrong; the scan shows 1),
all relative to the command byte.

**Declare Source File** (L4590-4740), offsets from the command byte:

| Off | Size | Field | Value |
|---|---|---|---|
| 0 | B | `DST$B_SRC_COMMAND` | 1 |
| 1 | B | `DST$B_SRC_DF_LENGTH` | bytes remaining in the command after this byte = 20 + n + m |
| 2 | B | `DST$B_SRC_DF_FLAGS` | 0 (reserved, MBZ) |
| 3 | W | `DST$W_SRC_DF_FILEID` | file ID (any small number, e.g. 1) |
| 5 | Q | `DST$Q_SRC_DF_RMS_CDT` | file creation date/time (`XAB$Q_CDT`), or a library module's insertion time |
| 13 | L | `DST$L_SRC_DF_RMS_EBK` | end-of-file block (`XAB$L_EBK`; 0 for a library module) |
| 17 | W | `DST$W_SRC_DF_RMS_FFB` | first free byte (`XAB$W_FFB`; 0 for a library module) |
| 19 | B | `DST$B_SRC_DF_RMS_RFO` | record format/organization (`XAB$B_RFO`; 0 for a library module) |
| 20 | B + n | `DST$B_SRC_DF_FILENAME` | counted ASCII: full resultant file spec (device, directory, version) |
| 21+n | B + m | `DST$B_SRC_DF_LIBMODNAME` | counted ASCII: library module name, or empty (m = 0) |

For poc (listing line = source line): one Source record with
`DECLFILE id=1 ...; SETFILE 1; SETREC_W 1; SETLNUM_W 1; DEFLINES_W N`
(N = number of lines; repeat `DEFLINES_W` for N > 65535), so line i maps
to record i. Doubt: whether the 5.5-2 debugger checks CDT/EBK/FFB against
the file it opens (and what it does when poc runs on Linux and the file
on VMS has another date and name); to test, with `SET SOURCE`.

---

## 5. Data symbols and their locations

### 5.1 Standard Data record (L1602-1721)

`DST$B_TYPE` is the symbol's VAX standard type code (1..37), or
`DST$K_BOOL` (158) for a Boolean (TRUE iff low bit set, one byte).

| Off | Size | Field | |
|---|---|---|---|
| 0 | B | `DST$B_LENGTH` | 7 + n |
| 1 | B | `DST$B_TYPE` | dtype or 158 |
| 2 | B | `DST$B_VFLAGS` | value flags, below |
| 3 | L | `DST$L_VALUE` | value, address, offset, register number, or bit offset |
| 7 | B | `DST$B_NAME` | n |
| 8 | n | — | symbol name |

`DST$B_VFLAGS` subfields (unless it holds a special value, 5.2):

| Bits | Field | |
|---|---|---|
| 0-1 | `DST$V_VALKIND` | 0 `DST$K_VALKIND_LITERAL` (VALUE is the value, <= 32 bits); 1 `DST$K_VALKIND_ADDR` (the computation gives the object's address); 2 `DST$K_VALKIND_DESC` (gives the address of a VAX descriptor for it); 3 `DST$K_VALKIND_REG` (the object is in the register whose number is in VALUE) |
| 2 | `DST$V_INDIRECT` | after the address is computed, fetch the longword there: it is the address (by-reference) |
| 3 | `DST$V_DISP` | add register REGNUM's contents to VALUE |
| 4-7 | `DST$V_REGNUM` | register for DISP (0-14; 15 = PC never occurs, so a VFLAGS with all top 4 bits set is special) |

[PDF p.39, p.47 for the bit positions; the OCR's "V_(5)" for DISP is
wrong, it is bit 3.]

Computation (L1685-1710): LITERAL → VALUE; REG → register VALUE;
otherwise addr := VALUE; if DISP, addr += R[REGNUM]; if INDIRECT,
addr := (addr); then ADDR → object at addr, DESC → descriptor at addr.

**Encodings for poc** (VALUE as a little-endian longword):

| Where the variable is | VFLAGS | VALUE |
|---|---|---|
| global/module variable at psect+off | 0x01 (ADDR) | address, relocated (`STA_Px; STO_PIDR`) |
| local at -n(FP) | 0xD9 = 13<<4 \| DISP \| ADDR | -n |
| value parameter at 4k(AP) | 0xC9 = 12<<4 \| DISP \| ADDR | 4k |
| VAR parameter (address at 4k(AP)) | 0xCD = 12<<4 \| DISP \| INDIRECT \| ADDR | 4k |
| local whose address is held at -n(FP) | 0xDD | -n |
| variable in register Rn | 0x03 (REG) | n |
| named constant (<= 32 bits) | 0x00 (LITERAL) | value |
| parameter passed by descriptor at 4k(AP) | 0xCE = 12<<4 \| DISP \| INDIRECT \| DESC | 4k |

(The file's own example, L1711-1721: second reference parameter =
REGNUM 12, VALUE 8, DISP 1, INDIRECT 1, VALKIND ADDR.)

A 64-bit or real constant does not fit; it needs a Trailing Value Spec
(5.4) with a literal of the right size. A register-held HUGEINT/LONGREAL
(two registers): VALKIND_REG names the first; that DEBUG takes Rn:Rn+1
for an 8-byte type is assumed, not stated.

### 5.2 Special `DST$B_VFLAGS` values (L1644-1672) [PDF p.39]

| Value | Name | Meaning |
|---|---|---|
| 128 (0x80) | `DST$K_VFLAGS_NOVAL` | no value: the record is a type (Record Begin only). The one special value without the top 4 bits set |
| 249 (0xF9) | `DST$K_VFLAGS_UNALLOC` | never allocated, no address |
| 250 (0xFA) | `DST$K_VFLAGS_DSC` | Descriptor Format record (5.3) |
| 251 (0xFB) | `DST$K_VFLAGS_TVS` | Trailing Value Spec record (5.4) |
| 253 (0xFD) | `DST$K_VS_FOLLOWS` | VS-Follows value spec (only inside a trailing value spec) |
| 255 (0xFF) | `DST$K_VFLAGS_BITOFFS` | VALUE is a bit offset (record components only) |

### 5.3 Descriptor Format record (L1725-1767)

Same as Standard Data, but VFLAGS = 250 and offset 3 is `DST$L_DSC_OFFS`,
the byte offset of an embedded VAX descriptor from `DST$A_DSC_BASE`
= offset 7 (the name's count byte): descriptor address = record + 7 +
DSC_OFFS, so with the descriptor right after the name, DSC_OFFS = 1 + n.
DST$B_TYPE is the dtype. "Used for all static arrays and other data
objects that can be described by VAX Standard Descriptors" with a static
address: the descriptor's `DSC$A_POINTER` (and `DSC$A_A0` for an array)
hold the static address, so they are relocated longwords. Not for FP/AP
data.

### 5.4 Trailing Value Specification record (L1771-1809)

Same as Standard Data, VFLAGS = 251, offset 3 is `DST$L_TVS_OFFSET`:
the value spec starts at record + 7 + TVS_OFFSET (= 1 + n when it
follows the name directly). The trailing value spec is "normally" a
VS-Follows spec (5.5).

### 5.5 Value Specifications (L1865-2095)

All begin with `DST$B_VS_VFLAGS` (byte 0 of the spec, the same as
`DST$B_VFLAGS` in a data record). Fields [PDF p.47], offsets from the
start of the value spec:

| Off | Field | |
|---|---|---|
| 0 | `DST$B_VS_VFLAGS` B | bits as in 5.1: `DST$V_VS_VALKIND` 0-1, `DST$V_VS_INDIRECT` 2, `DST$V_VS_DISP` 3, `DST$V_VS_REGNUM` 4-7 |
| 1 | `DST$L_VS_VALUE` L | standard value spec |
| 1 | `DST$L_VS_DSC_OFFS` L | (VFLAGS = 250) descriptor at spec + 5 + DSC_OFFS (`DST$A_VS_DSC_BASE` = 5) |
| 1 | `DST$L_VS_TVS_OFFSET` L | (VFLAGS = 251) next spec at spec + 5 + TVS_OFFSET (`DST$A_VS_TVS_BASE` = 5) |
| 1 | `DST$W_VS_LENGTH` W | (VFLAGS = 253) length of the spec not counting VFLAGS and VS_LENGTH |
| 3 | `DST$B_VS_ALLOC` B | (253) 1 `DST$K_VS_ALLOC_STAT` (a literal), 2 `DST$K_VS_ALLOC_DYN` (an address); DEBUG ignores it |
| 4 | `DST$A_VS_MATSPEC` | (253) the Materialization Specification |

So a **standard value spec** is 5 bytes: VFLAGS, VALUE (used e.g. for a
subrange bound: `00` + longword).

**Materialization Specification** (L1936-1973), offsets from MATSPEC:

| Off | Field | Values |
|---|---|---|
| 0 | `DST$B_MS_KIND` | 1 `DST$K_MS_BYTADDR` (a byte address); 2 `DST$K_MS_BITADDR` (byte address + bit offset, 2 longwords); 3 `DST$K_MS_BITOFFS` (bit offset in a record); 4 `DST$K_MS_RVAL` (a literal of any size); 5 `DST$K_MS_REG` (a register number); 6 `DST$K_MS_DSC` (a whole VAX descriptor) |
| 1 | `DST$B_MS_MECH` | 1 `DST$K_MS_MECH_RTNCALL` (call a compiler thunk); 2 `DST$K_MS_MECH_STK` (DST stack machine); 3 `DST$K_MS_MECH_RTN_NOFP` (thunk, FP not passed); MIN 1, MAX 3 |
| 2 | `DST$B_MS_FLAGBITS` | bit 0 `DST$V_MS_NOEVAL` (purpose unclear), bit 1 `DST$V_MS_DUMARG` (thunk returns > 1 longword via a buffer) |
| 3 | `DST$A_MS_MECH_SPEC` / `DST$L_MS_MECH_RTNADDR` | stack machine code (MECH 2), or the thunk's address L (MECH 1/3) |

**A VS-Follows spec with a stack-machine routine**:

```
FD                      VFLAGS = DST$K_VS_FOLLOWS
LL LL                   VS_LENGTH = 4 + code length
02                      ALLOC = DYN (address) / 01 STAT (literal)
kk                      MS_KIND
02                      MS_MECH = STK
00                      MS_FLAGBITS
code ... 17             stack machine code, ending in STOP (23 = 0x17)
```

### 5.6 The DST Stack Machine (L2138-2362) [PDF pp.54-57]

256 longword cells, growing toward lower addresses (like the VAX stack).
Registers are those of the symbol's own call frame. The value left on
top at STOP is the result; its size follows MS_KIND (1 L for BYTADDR,
2 L for BITADDR, any size for RVAL, a whole descriptor for DSC, with the
descriptor's first longword on top, i.e. at the lowest address).

| Op | Name | Operand | Effect |
|---|---|---|---|
| 0..15 | `DST$K_STK_PUSHR0`..`PUSHR11`, `PUSHRAP` (12), `PUSHRFP` (13), `PUSHRSP` (14), `PUSHRPC` (15) | — | push register |
| 16 | `DST$K_STK_PUSHIMB` | B | push sign-extended byte |
| 17 | `DST$K_STK_PUSHIMW` | W | push sign-extended word |
| 18 | `DST$K_STK_PUSHIML` | L | push longword |
| 24 | `DST$K_STK_PUSHIM_VAR` | B len, then len bytes | push the bytes, zero-padded to a longword multiple |
| 25 | `DST$K_STK_PUSHIMBU` | B | push zero-extended byte |
| 26 | `DST$K_STK_PUSHIMWU` | W | push zero-extended word |
| 20 | `DST$K_STK_PUSHINB` | — | pop addr, push sign-extended byte at addr |
| 21 | `DST$K_STK_PUSHINW` | — | ... word |
| 22 | `DST$K_STK_PUSHINL` | — | ... longword |
| 27 | `DST$K_STK_PUSHINBU` | — | ... zero-extended byte |
| 28 | `DST$K_STK_PUSHINWU` | — | ... zero-extended word |
| 19 | `DST$K_STK_ADD` | — | pop 2, push sum |
| 29 | `DST$K_STK_SUB` | — | pop 2, push **top - second** |
| 30 | `DST$K_STK_MULT` | — | pop 2, push product |
| 31 | `DST$K_STK_DIV` | — | pop 2, push **top / second** |
| 32 | `DST$K_STK_LSH` | — | shift second by top bits; pop both; push result |
| 33 | `DST$K_STK_ROT` | — | rotate second by top |
| 34 | `DST$K_STK_COP` | — | push a copy of top |
| 35 | `DST$K_STK_EXCH` | — | swap top two |
| 36 | `DST$K_STK_STO_B` | signed B offset | store top's low byte at SP + 4 + offset; pop |
| 37 | `DST$K_STK_STO_W` | signed B | ... word |
| 38 | `DST$K_STK_STO_L` | signed B | ... longword |
| 39 | `DST$K_STK_POP` | — | pop |
| 23 | `DST$K_STK_STOP` | — | stop; top is the value |
| 40 | `DST$K_STK_RTNCALL` | — | pop thunk addr; CALL it (args: register vector R0-R11,AP,FP,SP,PC,PSL; stack pointer); FP in R1; push R0 |
| 41 | `DST$K_STK_RTNCALL_ALT` | — | same, result in an octaword buffer, pushed |
| 44 | `DST$K_STK_RTN_NOFP` | — | routine call, no FP passed |
| 42 | `DST$K_STK_PUSH_OUTER_REC` | — | push address of the outermost enclosing record |
| 43 | `DST$K_STK_PUSH_INNER_REC` | — | push address of the innermost enclosing record |

`DST$K_STK_LOW` = 0, `DST$K_STK_HIGH` = 44. STARLET 1993 `$DSTDEF` names
0-23 `DST$K_STA_R00..R15`, `STA_IMM_B/W/L` (16-18), `OPR_ADD` (19),
`STA_REP_B/W/L` (20-22), `OPR_STOP` (23): the same codes.

Example, the address of an open array's data, the address being passed
at 4(AP): `0C 10 04 13 16 17` = PUSHRAP, PUSHIMB 4, ADD, PUSHINL, STOP
(but this simple case is just VFLAGS 0xCD, VALUE 4).

---

## 6. Types

### 6.1 One-byte types: VAX standard type codes (L952-1006) [PDF p.22]

The code goes in `DST$B_TYPE` of a Standard Data record, in an Atomic
Type Spec, or in a descriptor's `DSC$B_DTYPE`.

| Code | `DSC$K_DTYPE_` | | poc |
|---|---|---|---|
| 0 | Z | unspecified (may not appear in the DST) | |
| 1 | V | aligned bit | |
| 2 | BU | byte logical (unsigned) | `SYSTEM.CARD8`, `SYSTEM.BYTE` |
| 3 | WU | word logical | `CARD16` |
| 4 | LU | longword logical | `CARD32`, `CARD`, `ADDRESS`?, procedure values? |
| 5 | QU | quadword logical | `CARD64` |
| 6 | B | byte integer | `SHORTINT` (-O2), `INT8` |
| 7 | W | word integer | `INTEGER` (-O2), `INT16` |
| 8 | L | longword integer | `LONGINT` (-O2), `INT32` |
| 9 | Q | quadword integer | `HUGEINT`, `INT64` |
| 10 | F | F_floating | `REAL` |
| 11 | D | D_floating | (not used) |
| 12 | FC | F complex | |
| 13 | DC | D complex | |
| 14 | T | ASCII text | `CHAR`, `ARRAY n OF CHAR` (with a length) |
| 15-20 | NU, NL, NLO, NR, NRO, NZ | numeric strings | |
| 21 | P | packed decimal | |
| 22 | ZI | sequence of instructions | |
| 23 | ZEM | procedure entry mask | |
| 24 | DSC | descriptor | |
| 25 | OU | octaword logical | |
| 26 | O | octaword integer | |
| 27 | G | G_floating | `LONGREAL` |
| 28 | H | H_floating | |
| 29 | GC | G complex | |
| 30 | HC | H complex | |
| 31 | CIT | COBOL intermediate temporary | |
| 32 | BPV | bound procedure value | |
| 33 | BLV | bound label value | |
| 34 | VU | unaligned bit | |
| 35 | ADT | absolute date-time | |
| 36 | — | unused | |
| 37 | VT | varying text | |

`DSC$K_DTYPE_LOWEST` = 1, `HIGHEST` = 37. DEBUG-internal codes, **not
allowed in the DST** (L1007-1041): 38 AC, 39 AZ, 40 TF (Boolean), 41 SV,
42 SVU, 43 FIXED, 191 LITERAL.

**BOOLEAN** has no standard dtype: in a data record use record type
`DST$K_BOOL` = 158. Inside a type spec (array element, pointer target),
the text implies an Atomic Type Spec "for type ... boolean" exists
(L3052-3054) but never says what code goes in `DST$B_TS_ATOM_TYP`;
presumably 158. Unconfirmed. `SET` has no dtype either: a Set Type Spec
(6.4) or `DSC$K_DTYPE_LU` (shown as a number).

Descriptor classes (from STARLET, `rtl/vax/vms/DSCDEF.Mod`): 1 S, 2 D,
4 A, 10 NCA, 14 UBA (the array type spec allows A, NCA, UBA, L2807-2809).
Class A layout: `DSC$W_LENGTH` 0 (element length), `DSC$B_DTYPE` 2,
`DSC$B_CLASS` 3 (= 4), `DSC$A_POINTER` 4, `DSC$B_SCALE` 8, `DSC$B_DIGITS`
9, `DSC$B_AFLAGS` 10 (bit 4 `FL_REDIM`, 5 `FL_COLUMN`, 6 `FL_COEFF`
= multipliers present, 7 `FL_BOUNDS` = bounds present), `DSC$B_DIMCT`
11, `DSC$L_ARSIZE` 12 (bytes), `DSC$A_A0` 16, then M1..Mn (L each), then
L1,U1,...,Ln,Un (L each). One dimension, all blocks: 36 bytes.

### 6.2 Separate Type Specification record, `DST$K_SEPTYP` = 163 = 0xA3 (L1814-1861)

Same layout as a Standard Data record (VFLAGS at 2, VALUE at 3, name at
7), with type 0xA3; may be a TVS form (VFLAGS 251, trailing value spec
after the name). **Must be immediately followed** by a Type Specification,
Record Begin, or Enumeration Type Begin record giving the symbol's type
(only Continuation records may come between).

### 6.3 Type Specification record, `DST$K_TYPSPEC` = 175 = 0xAF (L2366-2400)

| Off | Size | Field |
|---|---|---|
| 0 | B | `DST$B_LENGTH` |
| 1 | B | `DST$B_TYPE` = 0xAF |
| 2 | B | `DST$B_TYPSPEC_NAME` n (0 if the type has no name) |
| 3 | n | type name |
| 3+n | var | `DST$A_TYPSPEC_TS_ADDR`: one DST Type Specification |

It either directly follows a Separate Type Spec record or is pointed to
by an Indirect (or Novel Length) Type Spec elsewhere in the module.

### 6.4 DST Type Specifications (L2405-3079) [PDF p.61]

General form, offsets from the start of the type spec:

| Off | Size | Field |
|---|---|---|
| 0 | W | `DST$W_TS_LENGTH`: length **not counting this word** |
| 2 | B | `DST$B_TS_KIND` |
| 3 | var | kind-specific |

Kinds:

| Kind | Name | Layout after KIND (offsets from spec start) | TS_LENGTH |
|---|---|---|---|
| 1 | `DST$K_TS_ATOM` | 3 B `DST$B_TS_ATOM_TYP` (dtype) | 2 (total 4 = `DST$K_TS_ATOM_LENG`) |
| 2 | `DST$K_TS_DSC` | 3 var `DST$A_TS_DSC_VSPEC_ADDR`: a value spec yielding a VAX descriptor | var |
| 3 | `DST$K_TS_IND` | 3 L `DST$L_TS_IND_PTR`: DST pointer (offset from start of the whole DST) to a Type Spec, Record Begin, or Enum Begin record | 5 (total 7) |
| 4 | `DST$K_TS_TPTR` | 3 var `DST$A_TS_TPTR_TSPEC_ADDR`: nested type spec of the target type | 1 + nested total |
| 5 | `DST$K_TS_PTR` | (none): untyped pointer | 1 (total 3) |
| 6 | `DST$K_TS_PIC` | picture (COBOL/PL/I) | — |
| 7 | `DST$K_TS_ARRAY` | see below | var |
| 8 | `DST$K_TS_SET` | 3 L `DST$L_TS_SET_LENG` (bits); 7 var `DST$A_TS_SET_PAR_TSPEC_ADDR` parent type spec | 5 + parent total |
| 9 | `DST$K_TS_SUBRANGE` | 3 L `DST$L_TS_SUBR_LENG` (bits); 7 var parent type spec; then value spec of lower bound; then value spec of upper bound | var |
| 10 | — | unused | |
| 11 | `DST$K_TS_FILE` | 3 B language; 4 var record type spec (optional) | |
| 12 | `DST$K_TS_AREA` | PL/I (not supported by DEBUG V4.0) | |
| 13 | `DST$K_TS_OFFSET` | PL/I (not supported by DEBUG V4.0) | |
| 14 | `DST$K_TS_NOV_LENG` | 3 L `DST$L_TS_NOV_LENG` (bits); 7 L `DST$L_TS_NOV_LENG_PAR_TSPEC` DST pointer to parent type record | 9 (total 11) |
| 15 | `DST$K_TS_IND_TSPEC` | DEBUG internal, cannot appear in the DST | |
| 16 | `DST$K_TS_SELF_REL_LABEL` | PL/I | 1 |
| 17 | `DST$K_TS_RFA` | BASIC record file address | |
| 18 | `DST$K_TS_TASK` | Ada task (not supported by DEBUG V4.0) | 1 |

`DST$K_TS_DTYPE_LOWEST` = 1, `HIGHEST` = 18. Fixed total lengths:
ATOM 4, IND 7, PTR 3, FILE 4, AREA 3, OFFSET 7, NOV_LENG 11 (OCR "14",
scan 11), TASK 3.

The **Indirect** type spec is the only way to refer to a record type from
another type spec (array element, pointer target, set parent): e.g.
`POINTER TO R` = TPTR containing IND -> R's Record Begin.

**Array Type Spec** (kind 7, L2751-2826):

| Off | Field |
|---|---|
| 0 | W TS_LENGTH |
| 2 | B KIND = 7 |
| 3 | B `DST$B_TS_ARRAY_DIM` = d |
| 4 | `DST$A_TS_ARRAY_FLAGS_ADDR`: bit vector of d+1 bits, rounded up to whole bytes: bit 0 = an element type spec is present; bit i = a type spec for subscript i is present |
| 4+ceil((d+1)/8) | value spec producing an array descriptor (class A, NCA or UBA): strides, bounds, element dtype |
| ... | element type spec, if bit 0 (then the descriptor's `DSC$B_DTYPE` should be 0) |
| ... | subscript type specs, for each set bit (omitted = longword integer) |

Used when the array has no compile-time-constant descriptor and none in
user memory (variable bounds), or when the element type cannot be
described by a descriptor (records, pointers, enums), L2816-2826.
Otherwise use a Standard Data record (if a run-time descriptor exists)
or a Descriptor Format record.

**Set Type Spec** for Oberon `SET`: `09 00 | 08 | 20 00 00 00 | 02 00 01 08`
= TS_LENGTH 9, KIND 8, 32 bits, parent ATOM `DTYPE_L`. Bit n = element n
(L2832-2859). Whether DEBUG displays it as a set under language UNKNOWN
is untested.

### 6.5 Record types (L3185-3367)

**Record Begin**, `DST$K_RECBEG` = 171 = 0xAB (L3315-3357):

| Off | Size | Field |
|---|---|---|
| 0 | B | `DST$B_LENGTH` = 11 + n |
| 1 | B | `DST$B_TYPE` = 0xAB |
| 2 | B | `DST$B_VFLAGS`: 0x80 NOVAL for a type definition (normal VFLAGS = also a record object, located as in Standard Data; TVS allowed) |
| 3 | L | `DST$L_VALUE` (0 with NOVAL) |
| 7 | B | `DST$B_NAME` n: type name (or object name) |
| 8 | n | name |
| 8+n | L | `DST$L_RECBEG_SIZE`: size of the record in **bits** (0 if unknown) |

**Record End**, `DST$K_RECEND` = 172 = 0xAC: `01 AC`.

Between them: one data record per component (Standard Data, Separate
Type Spec + its type record, etc.). Other records (type specs, nested
Record Begin/End used as types) may appear inside without being
components; only data records are components. Component "addresses are
bit or byte offsets from the start of the record" (L677-680): either
VFLAGS = 255 `DST$K_VFLAGS_BITOFFS` with VALUE = bit offset, or (the
text implies) VALKIND_ADDR with VALUE = byte offset; which one DEBUG V5.5
prefers is to be seen from a guest compiler's dump. A record component
of record type: Separate Type Spec (VFLAGS/VALUE = the offset) followed
by the Record Begin, or by a Type Spec with an Indirect spec.

An extended record (Oberon type extension) has no DST notion; poc lists
the base type's fields first, flattened.

A record variable `v: R`: Separate Type Spec `v` (location) + Record
Begin `R` (NOVAL) ... Record End, the first time; afterwards Separate
Type Spec `w` + Type Spec (IND -> R's Record Begin). (L620-720.)

Variant records (VARBEG 167, VARVAL 157 with tag ranges SINGLE 1 /
RANGE 2, VAREND 168, L3371-3560): not needed.

### 6.6 What the type machinery gives poc

| Oberon | DST |
|---|---|
| BOOLEAN variable | record type 158 |
| CHAR | Standard Data with `DTYPE_T` (length 1 assumed; unconfirmed), or `DTYPE_BU` |
| SHORTINT/INTEGER/LONGINT/HUGEINT | DTYPE B/W/L/Q (by size model) |
| REAL / LONGREAL | DTYPE F (10) / G (27) |
| SET | Separate Type Spec + Type Spec (TS_SET 32, parent L), or DTYPE_LU |
| fixed ARRAY n OF CHAR, global | Descriptor Format record, class S, DTYPE_T, length n |
| fixed array of basic type, global | Descriptor Format record, class A |
| fixed array, local or parameter, or of records/pointers | Separate Type Spec (location) + Type Spec with TS_ARRAY (descriptor value spec: a descriptor value spec, VFLAGS 250, pointing to a constant descriptor further in the record, or a VS-Follows; element type spec if not basic) |
| open array parameter (address at 4k(AP), length at 4j(AP)) | Separate Type Spec with VFLAGS 0xCD VALUE 4k + Type Spec with TS_ARRAY whose value spec is VS-Follows, MS_KIND 6 (DSC), stack machine building a class-A descriptor whose U1 = (4j(AP)) - 1 |
| record | Record Begin/End + Separate Type Spec, Indirect specs |
| POINTER TO record | Separate Type Spec + Type Spec: TPTR (IND -> Record Begin) |
| POINTER TO ARRAY (voc block layout) | TPTR to an array whose bounds live in the block header: no evident way to reach the pointer's value from the nested spec; TS_PTR (untyped) or TPTR to the header record as a fallback |
| procedure type value | no procedure type spec in V4.0: DTYPE_LU, or TS_PTR |
| named constant | Standard Data, VFLAGS 0, VALUE (<= 32 bits); wider via TVS with MS_RVAL |

Doubt on arrays not at a static address: what DEBUG does with the
descriptor's `DSC$A_POINTER`/`DSC$A_A0` when the actual address comes
from the Separate Type Spec's value spec. The obsolete COBOL Hack record
(L5293-5300) describes DEBUG putting the computed address in POINTER and
**adding** it to A0, which suggests A0 is written relative (as an offset)
in such descriptors; not stated for TS_ARRAY. To check against a VAX C
`auto` array or a FORTRAN array argument dump.

---

## 7. Everything else a module needs

### 7.1 Order and placement rules

1. Module Begin first, Module End last; one pair per object module.
2. Routine Begin/Routine End around each routine (Routine End mandatory
   since poc is not MACRO); nested routines nested inside.
3. Data records inside the scope that declares them.
4. A Separate Type Spec immediately before its type record.
5. A Prolog record right after its Routine Begin (optional).
6. Line number and Source records anywhere in the module; each stream in
   order.
7. A Type Spec pointed to by an Indirect spec: anywhere in the module
   (before or after the pointer).
8. A record longer than 255 bytes: the first record holds 100..255 bytes,
   then Continuation records `len AD text...` (L5144-5228); not allowed for
   Module/Routine/Block Begin, Label, Entry, PSECT, Line Number, Source,
   or fixed-size records. Allowed for Standard Data and variants, Separate
   Type Spec, Type Spec.

### 7.2 TBT versus DBG (L294-340)

- **TBT** (05, kept by a plain LINK): Module Begin/End, Routine Begin/End,
  Block Begin/End, **all Line Number PC-Correlation records**, and
  optionally Version Number. Enough for a traceback with routine names and
  line numbers.
- **DBG** (04, kept only by LINK/DEBUG): everything else (data, types,
  Source File Correlation, Prolog, Label).
- The linker cannot copy DBG without TBT; module/routine/block records
  must be written whenever any symbol information is, because they define
  the scopes. LINK/NOTRACEBACK drops both. A compiler's `/DEBUG=(NOTRACE,
  SYMBOLS)` leaves out only the line records.
- Since the linker treats both alike and they may be mixed (Linker manual
  7.8), the DST record stream is one sequence; poc decides per record
  which object record type carries it. (MACRO/DEBUG put its line numbers
  in DBG records, section 7 of the spec; DSTRECRDS says they belong in
  TBT, which gives line numbers in a traceback without /DEBUG.)

### 7.3 Small records

- **Version Number**, `DST$K_VERSION` = 153 = 0x99 (L5017-5037):
  `03 99 major minor`. Ignored by DEBUG except to tell compiler versions
  apart. Optional.
- **Label**, `DST$K_LABEL` = 187 = 0xBB (L3830-3870): 0 LENGTH 7+n,
  1 0xBB, 2 unused 0, 3 L code address (relocated), 7 counted name. For a
  label bound to an instruction; poc has none to show.
- **Entry Point**, 181 = 0xB5 (L3904-3925): same layout; a secondary
  entry of the enclosing routine, called with CALLS/CALLG. Never for the
  main entry.
- **PSECT**, 184 = 0xB8 (L3927-3981) [PDF p.99]: 0 LENGTH, 1 0xB8,
  2 `DST$B_PSECT_UNUSED` 0, 3 L `DST$L_PSECT_VALUE` (start address),
  7 B name count (`DST$B_PSECT_NAME`, also `DST$B_PSECT_TRLR_OFFS`),
  8 name, 8+n L `DST$L_PSECT_SIZE`. "Only used for language MACRO ...
  DEBUG ignores PSECT DST records for all other languages." poc may keep
  writing them (as MACRO does) or drop them once the language is not 0.
- **Static Link**, 156 = 0x9C (L4932-4981): `len 9C value-spec`, the value
  spec giving the FP of the statically enclosing invocation. Optional.
- **Definition Line Number**, 170 (L4902-4928): `06 AA 00 L line`, must
  follow the data record it describes; not supported by DEBUG V4.0.

### 7.4 The Debug Module Table

Built by the linker (LINK/DEBUG) from each module's DST size and psects
(L380-420); nothing for the compiler to write.

### 7.5 Records poc will never need (names only)

BLISS Special Cases (0) and BLISS Field (183); Enumeration Type
Begin/Element/End (165/164/166); Variant Set Begin/Value/End
(167/157/168) and tag range specs; COBOL Global Attribute (154); COBOL
Hack (178, obsolete); Overloaded Symbol (169, Ada); Label-or-Literal
(186, MACRO); Entry Point (181); Value Specification record (174,
ignored); Global-Is-Next (160) and External-Is-Next (159), obsolete;
Threaded-Code PC-Correlation (182, obsolete); type specs Picture (6),
File (11), Area (12), Offset (13), Self-Relative Label (16), RFA (17),
Task (18).

---

## 8. Doubts

Corrected from the scan (the OCR was wrong; now confirmed):
- `DST$K_UNKNOWN` = 10 (OCR 16); also `DSC$K_DTYPE_F` = 10 (OCR 16),
  `DST$K_STK_PUSHR10` = 10, `DST$K_TS_SUBRANGE` = 9 / unused 10.
  (`vax-object-language.md` section 12 question 3 had 16; corrected.)
- `DSC$K_DTYPE_ZI` 22, `ZEM` 23, `BPV` 32, `BLV` 33; `DST$K_BLISS` 2;
  `DST$K_RECEND` 172; `DST$K_LINE_NUM_REL_R11` 182.
- PC-correlation: `INCR_LINUM` 2, `INCR_LINUM_W` 3, `INCR_LINUM_L` 18,
  `SET_LINUM_L` 20, `SET_STMTNUM` 13, `SET_ABS_PC` 16, `DELTA_PC_L` 17.
- Source: `SRC_SETFILE` 2, `SRC_SETREC_L` 3; `DST$B_SRC_UNSBYTE` is at 1.
- Stack machine: `PUSHIMBU` 25, `PUSHINW` 21, `PUSHINL` 22, `STOP` 23,
  `RTN_NOFP` 44 (equal to `DST$K_STK_HIGH` 44; codes 42/43 are the record
  pushes).
- `DST$V_VS_DISP` / `DST$V_DISP` = bit 3 (OCR "5").
- `DST$K_TS_NOV_LENG_LENG` = 11 (OCR 14). `DST$B_PSECT_UNUSED` at 2.

Not checked against the scan (OCR plain and consistent): record codes
153-162 (listing p.21, PDF p.23); dtypes 1-20 (agree with STARLET).

Unresolved by this file:
1. `DST$K_SET_STMTNUM`: its literal says "Byte command", its description
   says an unsigned word. poc should not use statement mode.
2. How a DST pointer ("offset from the start of the whole DST") is built
   with the linker's `CTL_DFLOC`/`CTL_STKDL` (section 3.5). Needed for
   Indirect type specs, i.e. for any type used twice and every pointer to
   a record.
3. The atomic type code for BOOLEAN inside a type spec (158 assumed).
4. Record components by byte offset (VALKIND_ADDR) or bit offset (255).
5. CHAR as `DTYPE_T` in a Standard Data record (length 1 assumed).
   Answered on the guest: one character (`vax-object-language.md`
   16.7).
6. `DSC$A_POINTER`/`DSC$A_A0` in a TS_ARRAY descriptor for stack data.
7. Whether the source file's CDT/EBK/FFB must match for DEBUG to show it.
   Answered: no, a mismatch is only noted, NOTORIGSRC (16.6).
8. Line numbers out of PC order, or one line in several PC ranges.
   Answered: a line gets a stop at each range (16.5).
9. Which language code: 10 (UNKNOWN, officially unsupported) or 6
   (PASCAL); codes > 10 known to the 5.5-2 debugger are not in this
   file. Answered: 10, since with 6 the debugger refuses to deposit into
   any integer but a longword (16.7).
10. Everything here is V4.0 (1984); VMS 5.5-2's DEBUG may have added
    records (codes below 153, since new codes are allocated by decrementing
    `DST$K_LOWEST`) and type spec kinds (above 18). The stack machine
    0-23 is unchanged in 1993 STARLET; nothing else could be checked.
