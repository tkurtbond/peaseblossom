# VAX/VMS manuals to get

The VMS target is **VAX/VMS 5.5-2** (August 1992), so every fact poc's
VAX work (Phases 15-17 in `PLAN.md`) takes from documentation must come from
a manual for that release, or - where the set for 5.5-2 does not carry
the manual - from the nearest *earlier* 5.x release, checked against the 5.5
and 5.5-2 release notes for anything that changed. Manuals for other
releases are context only.

Save what is fetched in `~/Reference/Computer/OS/VMS/`, keeping the original
file name (it carries the DEC order number and the date). This document is
the to-do list. Downloaded so far: `AA-LA66B` (the calling standard) and
`AA-LA62A` (the Linker, with the object language), 2026-09-26.

## Status of the attempt

- 2026-09-19: a scripted `curl` of the 33 files below from
  `https://www.bitsavers.org/pdf/dec/vax/vms/` got **HTTP 403 for every one**
  (the directory listings themselves were readable through the web-fetch
  tool). Nothing was written to `~/Reference/Computer/OS/VMS/`. Before trying
  again, check whether the server wants a browser-like `User-Agent`, or use
  the Internet Archive copies (`archive.org` carries many of the same
  bitsavers files), or fetch by hand.
- 2026-09-26: a browser-like `User-Agent` is enough:
  `curl -f -A 'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101
  Firefox/130.0' -o <file> https://www.bitsavers.org/pdf/dec/vax/vms/<release>/<file>`.
  Fetched that way: `AA-LA66B-TE_Introduction_to_VMS_5.4_System_Routines_199006.pdf`
  (chapter 2 is the VAX Procedure Calling and Condition Handling Standard)
  and `AA-LA62A-TE_VMS_5.0_Linker_Utility_Manual_198804.pdf` (chapter 7 is
  the VAX object language), with `pdftotext -layout` extracts beside them
  (`*-layout.text`; the scans' OCR has character errors). The `5.1`-`5.3`
  directories were checked for a newer Linker manual: they have none, nor
  any calling-standard or object-language document.
- The file names below were transcribed from the bitsavers directory
  listings (`.../vms/5.5/`, `.../vms/5.4/`, `.../vms/5.0/`); confirm each on
  download.
- Not yet looked at: the `5.1`, `5.2` and `5.3` directories (a newer copy of
  a manual listed only under 5.0 may be there - the Linker, LIB$, STR$, SMG$
  and RMS manuals in particular), and the layered-product directories
  (`layered_product`, `gks`, etc.) for VAX MACRO, VAX C and VAX Pascal
  documentation at the versions 5.5-2's SPD lists.

## What we already have, by release

Local files under `~/Reference/Computer/OS/VMS/` (and `.../Systems/VAX/`),
and whether they are safe for 5.5-2 facts:

| Release of the manual | Files | Use for 5.5-2? |
|---|---|---|
| VMS 2.0 / 3.0 (1980-82) | `AA-D017B` System Messages, `AA-H782A`/`AA-H782B` Command Procedures | No - far too old |
| VMS 5.0 (April 1988) | `AA-LA89A` VAX MACRO and Instruction Set, `AA-LA81A` FDL, `AA-LA65A` SUMSLP, `AA-LA15A` DSR | Yes, with the release notes checked; MACRO 5.4 (below) supersedes the first |
| VMS 5.2 (June 1989) | `AA-LA40B` Guide to VMS System Security | Yes |
| VAX languages of the period | VAX C 3.0 guide (`AA-L370D`, Jan 1989), VAX C RTL (`AI-JP84A`, Mar 1987), VAX FORTRAN (`AA-D034E`/`AA-DO35E`, Jun 1988) | Probably - check the versions the 5.5-2 SPD lists |
| DEC MMS | `AA-P119B` (2.0, 1984), `AA-P119D` (May 1989) | The second; check which MMS version was current for 5.5-2 |
| VAX architecture | `EK-VAXAR-RM-003` Architecture Reference Manual, `DEC_VAX_Architecture_Handbook`, `VAX_archHbkVol1_1977` | Architecture, not OS - fine, but the 1977 handbook predates the final architecture |
| Handbooks | `VMS_Language_and_Tools_Handbook_1985`, `VMS_System_Software_Handbook_1985`, `VAX_Software_Handbook_1982` | Background only (VMS 4.x and earlier) |
| **Later than 5.5-2** | `AA-PV5RA` OpenVMS VAX 6.0 security guide (1993); `OVMS_PROG_ENVIRON.PDF` (March 1994, OpenVMS AXP 1.5 / VAX 6.0); `OpenVMS_RMS_RTL_Library.pdf` (June 2002, 7.3); `HP OpenVMS Programming Concepts Volume II` (2005); `guide-to-openvms-file-applications.pdf` and the `VSI/` and `HPE_*` files (2005-2019, Alpha/Itanium) | **No for facts** - may explain a concept (ASTs, in the 2005 volume) but every detail must be re-checked against a 5.5 manual |

## Priority 1 - defines the target

Directory: `https://www.bitsavers.org/pdf/dec/vax/vms/5.5/`

| File | Why |
|---|---|
| `AV-PQZAB-TE_VMS_5.5-2_Release_Notes_Aug1992.pdf` | What 5.5-2 itself changed; the delta on top of 5.5 |
| `AV-PSY0A-TE_VMS_Version_5.5-2_Update_Procedures_199208.pdf` | How a 5.5-2 system is put together from 5.5 (Phase 16 step 1) |
| `AE-PT7JA-TE_VMS_5.5_SPD_Aug1992.pdf` | The Software Product Description: exactly what is in the kit, and which layered-product versions are supported - answers "does the base system include MACRO and the linker?" (Phase 16 step 1) |
| `AA-LB22D-TE_VMS_Version_5.5_Release_Notes_Nov1991.pdf` | What 5.5 changed from 5.4 |
| `AA-LA97D-TE_VMS_Version_5.5_New_Features_Manual_Nov1991.pdf` | Feature changes since 5.4 |
| `AA-LA95D-TE_Overview_of_VMS_Documentation_V5.5_Nov1991.pdf` | Which manual covers what in the 5.5 set |
| `AA-LA56C-TE_VMS_5.5_Programming_Master_Index_199111.pdf` | Index across the whole programming set - finds which manual has a routine |

Also present in that directory, not requested yet: `AA-LA01C` Master Index,
`AA-LA03B` Glossary, `AA-LA59D` Debugger Manual, `AA-LB35D` Upgrade
Supplement, `AA-NG61D` Upgrade and Installation, `AA-NY74C` Upgrade
supplement for VAXstation 3100/4000 and MicroVAX 3100, and the 5.5-2H4
release notes and cover letter (a later hardware release - not 5.5-2 itself).

## Priority 2 - the 5.5 system-services manuals (Phase 16 step 4; Phase 17 steps 4-6)

Directory: `https://www.bitsavers.org/pdf/dec/vax/vms/5.5/`

| File | Why |
|---|---|
| `AA-LA69B-TE_VMS_5.5_System_Services_Reference_Manual_199111.pdf` | `$QIO`, `$SETIMR`, `$DCLAST`, `$SETAST`, `$SETEF`, `$WAITFR`, `$DCLEXH`, `$CRMPSC` ...: the AST and asynchrony design (Phase 17 step 6) and the runtime's memory and I/O calls |
| `AA-LA68B-TE_Introduction_to_VMS_5.5_System_Services_199111.pdf` | The concepts behind them: AST delivery rules, access modes, event flags |

## Priority 3 - not in the 5.5 directory, so the newest release that has them

**5.4** (`https://www.bitsavers.org/pdf/dec/vax/vms/5.4/`):

| File | Why |
|---|---|
| `AA-LA89B-TE_VAX_5.4_Macro_and_Instruction_Set_Reference_Manual_199006.pdf` | MACRO-32 itself - directives, addressing modes, program sections (Phases 15-17); newer than the 5.0 copy we have |
| `AA-LA66B-TE_Introduction_to_VMS_5.4_System_Routines_199006.pdf` | The calling standard and how routines are documented; condition handling |
| `AA-LA67B-TE_VMS_5.4_Utility_Routines_Manual_199006.pdf` | Librarian, Linker, Message and other utilities called as routines |
| `AA-LA72B-TE_VMS_5.4_RTL_Mathematics_MTH$_Manual_199006.pdf` | `MTH$` - floating-point library, F/D/G formats (Phase 16 step 3a; Phase 17 step 2) |
| `AA-LA84B-TE_VMS_5.4_IO_Users_Reference_Manual_Part_1_199006.pdf` | `$QIO` function codes and device drivers' arguments (Phase 17 step 6) |
| `AA-PBK5A-TE_VMS_5.4_DCL_Dictionary_Part_1_199006.pdf` and `AA-PBK6A-TE_VMS_5.4_DCL_Dictionary_Part_2_199006.pdf` | `MACRO`, `LINK`, `LIBRARY`, `INSTALL`, `RUN`, `DEFINE`, `SET` - every command the toolchain driver issues (Phase 16 step 2) |

**5.0** (`https://www.bitsavers.org/pdf/dec/vax/vms/5.0/`) - the only release listed
for these; check `5.1`-`5.3` for newer copies first:

| File | Why |
|---|---|
| `AA-LA62A-TE_VMS_5.0_Linker_Utility_Manual_198804.pdf` | `LINK`, shareable images, transfer vectors, `GSMATCH`, program-section attributes (Phase 17 step 1) |
| `AA-LA61A-TE_VMS_5.0_Librarian_Utility_Manual_198804.pdf` | Object and macro libraries (`.OLB`, `.MLB`) (Phase 17 step 1) |
| `AA-LA29A-TE_VMS_5.0_Install_Utility_Manual_198804.pdf` | Installing shareable images (Phase 17 step 1) |
| `AA-LA76A-TE_VMS_5.0_RTL_Library_LIB$_Manual_198804.pdf` | `LIB$` - `LIB$GET_VM`, `LIB$GET_FOREIGN`, `LIB$SIGNAL`, `LIB$STOP` (Phase 16 step 4; Phase 17 step 4) |
| `AA-LA75A-TE_VMS_5.0_RTL_String_Manipulation_STR$_Manual_198804.pdf` | `STR$` and string descriptors (Phase 17 step 5) |
| `AA-LA77A-TE_VMS_5.0_RTL_Screen_Managment_SMG$_Manual_198804.pdf` | `SMG$` (Phase 17 step 4) |
| `AA-LA73A-TE_VMS_5.0_RTL_General_Purpose_OTS$_Manual_198804.pdf` | `OTS$` language-support routines (Phase 17 step 4) |
| `AA-LA70A-TE_Introduction_to_the_VMS_5.0_Run-Time_Library_198804.pdf` | How the RTL families fit together |
| `AA-LA83A-TE_VMS_5.0_Record_Management_Services_Manual_198804.pdf` | RMS `FAB`/`RAB`, `$OPEN`/`$GET`/`$PUT` - the `Files` module's foundation (Phase 16 step 4) |
| `AA-LA78A-TE_Guide_to_VMS_5.0_File_Applications_198804.pdf` | Using RMS: record formats and access (Phase 16 step 4) |
| `AA-LA85A-TE_VMS_5.0_IO_Users_Reference_Manual_Part_2_198804.pdf` | The rest of the `$QIO` reference |
| `AA-LA06A-TE_Guide_to_VMS_5.0_Files_and_Devices_198804.pdf` | ODS-2 file names, versions and directories (Phase 16 step 4) |
| `AA-LA57A-TE_Guide_to_VMS_5.0_Programming_Resources_198804.pdf` | The programming environment as a whole |
| `AA-LA58A-TE_Guide_to_Creating_VMS_5.0_Modular_Procedures_198804.pdf` | Writing callable procedures to the calling standard |
| `AA-LA60A-TE_VMS_5.0_Command_Definition_Utility_Manual_198804.pdf` | CLD - a command verb for `poc` (Phase 16 step 4) |
| `AA-LA63A-TE_VMS_5.0_Message_Utility_Manual_198804.pdf` | Message files and condition codes |
| `AA-LA11A-TE_Guide_to_Using_VMS_5.0_Command_Procedures_198804.pdf` | DCL command procedures for the guest-side build (Phase 16 step 5) |

## Still to find

Not on the listings looked at so far, so the location is unknown:

- The **VAX Procedure Calling and Condition Handling Standard** as its own
  document (it is described in the system-routines and architecture manuals,
  but the standard itself is the authority for Phase 16 step 3b). Chapter 2
  of `AA-LA66B` (downloaded) describes it at length; a standalone copy is
  not on bitsavers' `vax/vms` listings.
- A **5.5-era Linker manual**, **LIB$ manual** and **RMS reference** - only
  5.0 copies were listed, and `5.1`-`5.3` have none (checked 2026-09-26
  for the Linker). The Internet Archive is still to be checked.
- The **VMS Programming Concepts** volumes (AST delivery in prose, the
  `$SETAST` rules) at a 5.x release - only the 2005 volume is held locally.
- The **object language** reference for VMS 5.5-2 (record formats for the
  module header, GSD, TIR, debug and traceback records, EOM): **found** as
  chapter 7 of the 5.0 Linker manual (`AA-LA62A`, downloaded; no newer
  Linker manual on bitsavers), to be checked against the 5.5 and 5.5-2
  release notes. Still wanted: the `ANALYZE/OBJECT` description; needed by Phase 18 step 1 before anything is
  designed. Also the **VAX instruction encoding** tables (opcode and
  operand-specifier formats), which the architecture reference and the
  MACRO manual carry, for Phase 18 step 3.
- **VAX MACRO** and **DEC MMS** release notes for the versions bundled or
  supported with 5.5-2 (the SPD will say which).
- Anything the 5.5-2 SPD names as required for a self-hosted build that the
  base kit lacks.
