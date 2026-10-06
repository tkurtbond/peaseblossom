# VAX/VMS manuals to get

The VMS target is **VAX/VMS 5.5-2** (August 1992), so every fact poc's
VAX work (Phases 15-17 in `PLAN.md`) takes from documentation must come from
a manual for that release, or - where the set for 5.5-2 does not carry
the manual - from the nearest *earlier* 5.x release, checked against the 5.5
and 5.5-2 release notes for anything that changed. Manuals for other
releases are context only.

Save what is fetched in `~/Reference/Computer/OS/VMS/`, keeping the original
file name (it carries the DEC order number and the date). This document is
the to-do list. Downloaded: `AA-LA66B` (the calling standard) and
`AA-LA62A` (the Linker, with the object language), 2026-09-26; **every
file in Priorities 1-3 below**, the MMS guide `AA-P119E` and DEC STD 032,
2026-10-05; the Digital Press *VAX Architecture Reference Manual*
(`EY-3459E-DP`), *VAX/VMS Internals and Data Structures: Version 5.2*
(`EY-C171E-DP`) and *VMS File System Internals* (`EY-F575E-DP`),
2026-10-06. What remains is under "Still to find".

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
- 2026-10-05: the other 31 files fetched the same way (the last 19 into a
  staging directory first, then moved here with `mv -n`), and every one
  checked with `file` and `pdfinfo` (all PDFs, page counts as expected).
  Also fetched:
  `AA-P119E-TE_Guide_to_VAX_DEC_Module_Management_System_199007.pdf` (from
  `vms/layered_product/MMS/`; newer than `AA-P119D`) and
  `EL-00032-00-decStd32_Jan90.pdf`, DEC STD 032, the VAX Architecture
  Standard (from `https://www.bitsavers.org/pdf/dec/vax/archSpec/`; saved in
  `~/Reference/Computer/Systems/VAX/`). Findings:
  - The `5.1`, `5.2` and `5.3` directories have only release notes, new
    features, installation and system-management manuals - no programming
    manual - so the 5.0 copies in Priority 3 are the newest on bitsavers.
  - `vms/SPD/` has only 5.1 SPDs; the 5.5 SPD is the one in `vms/5.5/`.
  - `vms/6.0/` has only installation manuals.
  - There is no standalone calling standard anywhere under `vax/vms`.
- 2026-10-06: fetched the same way, each with a `-layout.text` extract
  (all three have an OCR text layer, Acrobat's Paper Capture):
  - `EY-3459E-DP_VAX_Architecture_Reference_Manual_1987.pdf` (Digital
    Press, ed. Leonard, 433 pages; from
    `https://www.bitsavers.org/pdf/dec/vax/archSpec/`; saved in
    `~/Reference/Computer/Systems/VAX/`). The searchable architecture
    reference: `EK-VAXAR-RM-003` (1985) and DEC STD 032 are scans
    without text. The second edition (ed. Brunner, Digital Press, 1991)
    is not on bitsavers; the user has a paper copy.
  - `EY-C171E-DP_VMS_Internals_and_Data_Structures_5.2_1991.pdf`
    (Goldenberg and Kenah, Digital Press, 1462 pages) and
    `EY-F575E-DP_VMS_File_System_Internals_1990.pdf` (McCoy, Digital
    Press, 478 pages), from `.../vms/training/`; saved in
    `~/Reference/Computer/OS/VMS/`. The same directory has the 1984 and
    4.4 (1988) editions of the first, and DEC's internals course
    workbooks and listings.
- The file names below were transcribed from the bitsavers directory
  listings (`.../vms/5.5/`, `.../vms/5.4/`, `.../vms/5.0/`); confirm each on
  download.
- Not yet looked at: the layered-product directories (`layered_product`
  other than `MMS`, `gks`, etc.) for VAX C and VAX Pascal documentation at
  the versions 5.5-2's SPD lists.

## What we already have, by release

Local files under `~/Reference/Computer/OS/VMS/` (and `.../Systems/VAX/`),
and whether they are safe for 5.5-2 facts:

| Release of the manual | Files | Use for 5.5-2? |
|---|---|---|
| VMS 2.0 / 3.0 (1980-82) | `AA-D017B` System Messages, `AA-H782A`/`AA-H782B` Command Procedures | No - far too old |
| VMS 5.0 (April 1988) | `AA-LA89A` VAX MACRO and Instruction Set, `AA-LA81A` FDL, `AA-LA65A` SUMSLP, `AA-LA15A` DSR | Yes, with the release notes checked; MACRO 5.4 (below) supersedes the first |
| VMS 5.2 (June 1989) | `AA-LA40B` Guide to VMS System Security | Yes |
| VAX languages of the period | VAX C 3.0 guide (`AA-L370D`, Jan 1989), VAX C RTL (`AI-JP84A`, Mar 1987), VAX FORTRAN (`AA-D034E`/`AA-DO35E`, Jun 1988) | Probably - check the versions the 5.5-2 SPD lists |
| DEC MMS | `AA-P119B` (2.0, 1984), `AA-P119D` (May 1989), `AA-P119E` (July 1990) | The last; check which MMS version was current for 5.5-2 |
| VAX architecture | `EY-3459E-DP` Architecture Reference Manual (Digital Press, 1987; searchable), `EL-00032-00` DEC STD 032 (January 1990), `EK-VAXAR-RM-003` Architecture Reference Manual (1985), `DEC_VAX_Architecture_Handbook`, `VAX_archHbkVol1_1977` | Architecture, not OS - fine, but the 1977 handbook predates the final architecture; the user has the 1991 second edition on paper |
| VMS internals | `EY-C171E-DP` VAX/VMS Internals and Data Structures, Version 5.2 (1991); `EY-F575E-DP` VMS File System Internals (1990) | Yes for how 5.x works inside, with the 5.5 and 5.5-2 release notes checked; the documented interfaces (system services, RMS) still come from the manuals |
| Handbooks | `VMS_Language_and_Tools_Handbook_1985`, `VMS_System_Software_Handbook_1985`, `VAX_Software_Handbook_1982` | Background only (VMS 4.x and earlier) |
| **Later than 5.5-2** | `AA-PV5RA` OpenVMS VAX 6.0 security guide (1993); `OVMS_PROG_ENVIRON.PDF` (March 1994, OpenVMS AXP 1.5 / VAX 6.0); `OpenVMS_RMS_RTL_Library.pdf` (June 2002, 7.3); `HP OpenVMS Programming Concepts Volume II` (2005); `AA-PV69B` OpenVMS Calling Standard (March 1994, 6.1; see "The calling standard"); `guide-to-openvms-file-applications.pdf` and the `VSI/` and `HPE_*` files (2005-2019, Alpha/Itanium) | **No for facts** - may explain a concept (ASTs, in the 2005 volume) but every detail must be re-checked against a 5.5 manual |

## Priority 1 - defines the target (all downloaded)

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

## Priority 2 - the 5.5 system-services manuals (Phase 16 step 4; Phase 17 steps 4-6) (all downloaded)

Directory: `https://www.bitsavers.org/pdf/dec/vax/vms/5.5/`

| File | Why |
|---|---|
| `AA-LA69B-TE_VMS_5.5_System_Services_Reference_Manual_199111.pdf` | `$QIO`, `$SETIMR`, `$DCLAST`, `$SETAST`, `$SETEF`, `$WAITFR`, `$DCLEXH`, `$CRMPSC` ...: the AST and asynchrony design (Phase 17 step 6) and the runtime's memory and I/O calls |
| `AA-LA68B-TE_Introduction_to_VMS_5.5_System_Services_199111.pdf` | The concepts behind them: AST delivery rules, access modes, event flags |

## Priority 3 - not in the 5.5 directory, so the newest release that has them (all downloaded)

These are not stand-ins. Table 6 of the 5.5 *Overview of VMS
Documentation* (`AA-LA95D`, "Order Numbers for Manuals in the Programming
Subkit") and its tables for the other subkits give, for the 5.5 kit, the
same order number and revision letter as every manual in this section,
the 5.4 ones and the 5.0 ones: DEC shipped them unrevised with
5.5 (the Linker is still `AA-LA62A`, LIB$ `AA-LA76A`, RMS `AA-LA83A`). So
each is the 5.5 documentation set's own edition; check the 5.5 and 5.5-2
release notes for what changed after it was printed. A search of the
Internet Archive on 2026-10-05 also found no later revision (`AA-LA62B`,
`AA-LA76B`, `AA-LA83B` and the like), and its undated "VMS Linker
Utility Manual" and "VMS Record Management Services Reference Manual" are
the same `AA-LA62A` and `AA-LA83A`.

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
for these; `5.1`-`5.3` have no newer copies (checked 2026-10-05):

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

## The calling standard

The **VAX Procedure Calling and Condition Handling Standard** for VMS 5.x
is chapter 2 of `AA-LA66B`, *Introduction to VMS System Routines* (5.4,
June 1990; downloaded): the 5.x documentation set carries the standard
there, not as a book of its own, so that chapter is the authority for
Phase 16 step 3b, checked against the 5.5 and 5.5-2 release notes.
`AA-LA70A` (Introduction to the RTL) and `AA-LA58A` (Modular Procedures)
cover it from the caller's side.

The earliest standalone edition found, the *OpenVMS Calling Standard*
(`AA-PV69B-TK_OpenVMS_6.1_OpenVMS_Calling_Standard_Mar94.pdf`, OpenVMS AXP
and VAX 6.1, March 1994; chapter 2 is "OpenVMS VAX Conventions"), was
downloaded 2026-10-05 from the Internet Archive
(`https://archive.org/details/stx_AA-PV69B-TK_OpenVMS_6.1_OpenVMS_Calling_Standard_Mar94`).
It is later than 5.5-2, so it is a **secondary** source: it may explain a
point `AA-LA66B` leaves unclear, but a fact taken from it must be found in
`AA-LA66B` or a 5.5 manual too. The Internet Archive has no earlier
standalone edition (searched 2026-10-05). Before VMS 5 the standard was
already in the system-routines book: the 4.4 Run-Time Library reference
manual (`AA-Z502C`, April 1986, on the Internet Archive) says it "is
documented in Section 2.5 of the Introduction to System Routines".

## Still to find

Not on the listings looked at so far, so the location is unknown:

- The **VMS Programming Concepts** volumes (AST delivery in prose, the
  `$SETAST` rules) at a 5.x release - only the 2005 volume is held locally.
- The **object language** reference for VMS 5.5-2 (record formats for the
  module header, GSD, TIR, debug and traceback records, EOM): **found** as
  chapter 7 of the 5.0 Linker manual (`AA-LA62A`, downloaded; no newer
  Linker manual on bitsavers), to be checked against the 5.5 and 5.5-2
  release notes. Still wanted: the `ANALYZE/OBJECT` description; needed by Phase 18 step 1 before anything is
  designed. Also the **VAX instruction encoding** tables (opcode and
  operand-specifier formats), which the architecture reference and the
  MACRO manual carry, for Phase 18 step 3: now held in DEC STD 032 and
  the 5.4 MACRO manual (`AA-LA89B`).
- **VAX MACRO** and **DEC MMS** release notes for the versions bundled or
  supported with 5.5-2 (the SPD will say which).
- Anything the 5.5-2 SPD names as required for a self-hosted build that the
  base kit lacks.
