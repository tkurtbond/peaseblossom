# Phase 18 — Direct VAX/VMS object files (no MACRO-32 in the loop)

Moved here from `PLAN.md` on 2026-10-21, once the phase was done, with
the exit review written at the close-out. `PLAN.md` keeps the heading,
the goal and a list of the steps. The specification of the object
language poc writes, the design behind each step, every decision with
its date, and each piece's record are in
`doc/developer/vax-object-language.md`: sections 1-12 the object
language from `AA-LA62A` and MACRO's own objects, section 13 step 2's
representation, section 14 step 3's encoder, section 15 step 4's
writer, section 16 step 5's traceback and debugger records, section 17
step 6's wiring, and section 18 step 7's bootstrap and this gate.

The phase's text in `PLAN.md`, as it stood:

**Goal**: `poc` writes VAX/VMS object modules (`.OBJ`) itself, so a
compile is Oberon source to object file and `LINK` is the only VMS tool
left in the build - the assembler (`MACRO`) drops out. Phases 15-17 emit
MACRO-32 text and hand it to the assembler; that stays as `-emit-mar`, the
human-readable form the earlier phases reviewed and a debugging aid (and
the oracle this phase tests against), but it stops being the path a normal
build takes. Reasons to do it, to be checked and not assumed: the
assembler is one less tool that has to be present and fast on the guest
(Phase 16 step 1 confirms from the 5.5-2 SPD what the base kit contains);
a compile that produces its object directly does one pass over the code
instead of two; and poc controls exactly what goes into the object, the
debug and traceback information included.

**Explicit non-goals**: writing executable *images* (`LINK` stays - it
also builds shareable images, applies the option file, and is what
Phase 17's libraries rely on); writing object *libraries* (`LIBRARY`
stays); any object format other than VAX/VMS's (no ELF, no COFF), and any
VMS release but 5.5-2; a MACRO-compatible assembler for hand-written
MACRO-32 - only the subset poc itself emits has to be encoded.

1. **The object language, from the 5.5-2 documentation.** The VAX/VMS
   object module is a sequence of variable-length records of a few kinds -
   the module header (`HDR`), the global symbol directory (`GSD`: program
   sections, global symbol definitions and references, entry points), the
   text-information-and-relocation records (`TIR`: the code and data
   bytes, and relocation expressed as a small stack language), debug and
   traceback records (`DBG`/`TBT`), and the end of module (`EOM`) - as the
   linker and the object-language documentation describe them, all to be
   confirmed against the manuals for this release (`vax-vms-manuals-to-get.md`
   lists what is still to be found, the object-language reference among
   it). Write a specification, in this plan or a file it names, of exactly
   the subset poc needs: each record kind and field, the program-section
   attributes it uses, how a global symbol and an entry point with its
   register-save mask are expressed, how relocation against another
   module's symbol or a program-section base is written, the limits (the
   31-character symbol length again - Phase 15's mangling is unchanged),
   and the on-disk form (an object file is a record-oriented RMS file, so a
   file merely copied from another system's byte stream is *not* an object
   the linker accepts until its record attributes are set; `FDL` and
   `CONVERT` are the guest-side tools, and `Files` on VMS (Phase 16 step 4)
   is what lets poc write records directly). Read real objects first: what
   `MACRO` produces for each of the Phase 15 fixtures, dumped with
   `ANALYZE/OBJECT` and in hex, is the ground truth the specification is
   checked against. The specification is `doc/developer/vax-object-language.md`
   (a draft since 2026-10-18, from chapter 7 of `AA-LA62A` and eight
   fixtures' objects; its section 10 holds what is still open).

2. **An instruction-level representation under the code generator.**
   `VaxCodeGenerator.Mod` today writes MACRO-32 text as it walks the tree.
   To write bytes the same decisions must be available as data: a
   `VaxInstruction` representation (opcode, operand specifiers with
   addressing mode, register, displacement and symbol, labels, directives)
   built once, and two consumers of it - the existing text printer, which
   must produce exactly the `.mar` the Phase 15 fixtures already hold, and
   the new encoder. The refactor is done first and on its own, with the
   `expected-vax.mar` fixtures (and the runnable Phase 16 ones) as the
   safety net: nothing about the emitted assembly may change. The subset of
   MACRO-32 poc's generator uses is written down here, since it is what
   the encoder must cover and not a line more.
   **Done 2026-10-18**, in five pieces (2a-2e; the design and the subset
   are `doc/developer/vax-object-language.md` section 13):
   `src/back/vax/VaxInstructions.Mod` holds a module as one list of
   lines - instructions with operand specifiers, directives with items,
   labels, direct assignments, and comments, the only text - each with
   its statement's source position. After every piece the 110 VAX
   fixtures passed and poc's own source compiled for the VAX (35
   modules) was byte for byte what it had been.

3. **The instruction encoder.** VAX instructions are an opcode (one or
   two bytes) followed by operand specifiers, each a mode nibble and a
   register with any immediate, displacement or index bytes after it -
   the assembler's job that poc now does itself: label and
   program-section layout, displacement sizes, PC-relative references,
   `.ENTRY` masks, real literals converted to `F_floating`/`G_floating`
   bits (correctly rounded, half to even, as MACRO does; short literals
   where the value fits), and the data directives the generator emits
   (`.LONG`, `.WORD`, `.BYTE`, `.ASCIC`/`.ASCII`, `.BLKx`, `.ALIGN`).
   The design is `vax-object-language.md` section 14 (decided with
   the user 2026-10-18). Displacement sizes follow MACRO's one-pass rule, not relaxation to a
   fixpoint (decided with the user 2026-10-18; `vax-object-language.md`,
   section 6.2): a backward reference in the same program section gets
   the shortest displacement that reaches, every other reference a
   longword; poc writes branch instructions only over short, fixed
   distances already. Relaxing forward references for shorter code is a
   possible later optimization, which would end the byte-for-byte
   comparison. **Testing**: byte-for-
   byte comparison of the encoded text of every fixture module against the
   text `MACRO` produces from the same `.mar` on the guest - not merely
   "the linked program runs", since a wrong encoding that happens to run is
   the failure this step exists to catch - with the differences that are
   legitimate (an assembler's choice between equivalent encodings) listed
   and explained, not waved through.
   **3a done 2026-10-18** (`vax-object-language.md` section 14.7):
   `src/back/vax/VaxImage.Mod`, the image and its printer;
   `build/bin/vax-image` (`make vax-image`) and `tools/vax-macro-image`,
   MACRO's images of the 62 fixtures and of poc's own 35 modules, the
   reader checked against MACRO's listings; the four open questions
   answered; the fixture `vax-image-reader`.
   **3b done 2026-10-18** (section 14.8): `src/back/vax/VaxOpcodes.Mod`,
   164 instructions, checked against MACRO, Appendix D and Chapter 9.
   **3c and 3d done 2026-10-18** (section 14.9):
   `src/back/vax/VaxEncoder.Mod` and `poc -emit-vax-image`; the images of
   all 62 fixtures and all 35 of poc's own modules are MACRO's, byte for
   byte.
   **3e done 2026-10-18** (section 14.10): every VAX fixture compares
   poc's image of each module with MACRO's (`expected-vax.image`, 101
   images), on every host; the coverage fixture `vax-encoder-forms` adds
   every instruction and form the fixtures miss, and found two MACRO
   choices the encoder now makes (`0(Rn)` as `(Rn)`, a quadword immediate
   zero-extended) and a truncation it now refuses; poc's own 39 modules
   for the VAX are MACRO's, byte for byte. **Step 3 done.**

4. **The object writer, `VaxObjectWriter.Mod`.** From the encoded
   program sections write the records step 1 specified: the header, one
   `GSD` entry per program section and global symbol, the code and data as
   `TIR` with relocation for every symbolic reference the encoder could not
   resolve within the module (calls to other modules' procedures, the
   type-descriptor and string-constant symbols, external `["VMS"]`
   routines), and the end record. Phase 17's requirements ride on it:
   position-independent code and the program-section attributes a shareable
   image needs, universal (exported) symbols, and entry points a transfer
   vector can name. **Testing**: `ANALYZE/OBJECT` on poc's output and
   on `MACRO`'s for the same source, compared; and the decisive test, `LINK`
   accepts it and the program runs. The design is
   `vax-object-language.md` section 15 (decided with the user
   2026-10-18): the records from the encoder's image, through
   `ObjectRecords` (counted on Linux and the BSDs, RMS records on VMS),
   converted on the guest by `ObjectConvert`; every fixture's object read
   back and compared with MACRO's image on every host; `ANALYZE/OBJECT`,
   and two programs linked from poc's objects and run, on the guest.
   **4a done 2026-10-18** (section 15.7): `VaxObjectWriter.Mod`, the
   host `ObjectRecords`, `-emit-vax-object`; every fixture's object, and
   poc's own 41 modules', read back by `vax-image` give MACRO's image.
   **4b done 2026-10-18** (section 15.8): `vax-image -records`, the
   fixture `vax-object-records`, and `vax-encoder-forms`'s object.
   **4c done 2026-10-18** (sections 15.9, approved, and 15.10):
   `RecordFiles`, the VMS `ObjectRecords`, `OBJCONVERT`, binary FTP; every
   VAX fixture's objects converted on the guest and checked by
   `ANALYZE/OBJECT`.
   **4d done 2026-10-18** (section 15.11): `vax-cardinal` and
   `vax-for-loop-end` link their programs from poc's objects, with only
   `PocRtl` from MACRO, and they print what the MACRO-built ones print.
   `ANALYZE/OBJECT` checks poc's objects alone; MACRO's are compared
   through their images, byte for byte, which says more. **Step 4
   done.**

5. **Debug and traceback information.** The traceback records (`TBT`)
   that let an unhandled condition print a routine traceback, as MACRO's
   objects have them today, and **full debugger support** (decided with
   the user 2026-10-18): a program poc builds can be debugged in the
   VMS 5.5-2 debugger by Oberon source line - breakpoints, stepping,
   routine names, and variables with their types (basic types, records,
   arrays, pointers, procedure types). That needs the source position the
   front end already carries (every node has a line and column) threaded
   down to the encoder, which step 2's representation holds from the
   start, and Oberon's types in the debugger's DST records. The DST
   format is not in the 5.x manuals we have; finding it, and reading the
   DBG records of the guest's VAX C, FORTRAN, BASIC and Ada compilers,
   is the step's first part (`vax-object-language.md`, section 11).
   Whatever cannot be shown is recorded with the reason.
   The design is `vax-object-language.md` section 16 (decided with the
   user 2026-10-18): TBT records (modules, routines, line numbers) in
   every object, DBG records (source file, prologs, variables and their
   types) with `-g`, Oberon's names, the language chosen on the guest;
   pieces 5a-5e. **5a done** (section 16.5): TBT records in every
   object - modules, routines nested, line numbers - and a traceback and
   breakpoints and steps by line on the guest (`vax-traceback`); nested
   procedures now follow their root, which the traceback needs; names in
   capitals; the language left to 5c. **5b done** (section 16.6): `-g`
   gives the VAX objects the Source File Correlation and Prolog records;
   `TYPE` and the source at each break on the guest; on VMS the source's
   resultant name and RMS attributes (`RecordFiles.Describe`,
   `POC_RECORD_ATTRIBUTES`), which spare the debugger's NOTORIGSRC note.
   **5c done** (section 16.7): `-g` describes each variable and constant
   of a basic type - module variables, parameters, locals - which the
   debugger examines, deposits and evaluates on the guest
   (`vax-debug-records`); the language is `DST$K_UNKNOWN`, since
   Pascal's refuses to deposit into any integer but a longword.
   **5d done** (section 16.8): records (each once, by Indirect
   specifications, holes for forward references), pointers, procedure
   variables, sets, fixed arrays and open array parameters (a stack
   machine routine building the descriptor), all shown and deposited
   into on the guest (`vax-debug-records`); UNKNOWN confirmed.
   **5e done** (section 16.9): what the debugger cannot show, each with
   its reason; the VAX/VMS Guide's chapter 16 has "poc's own objects",
   a traceback by Oberon line and a debugger session, both run on the
   guest by `doc-vax-guide`; poc(1) and the Reference Guide's `-g`.
   **Step 5 done** (2026-10-19).

6. **Wiring it in.** A new mode (`-emit-obj`, and the default on VMS,
   with `-emit-mar` keeping the Phase 15 behavior) writes `<module>.OBJ`;
   `VaxToolchainDriver.Mod` stops invoking `MACRO`. The design, proposed
   2026-10-19 and approved, is `vax-object-language.md` section 17
   (pieces 6a-6e). **6a done** (section 17.3): `-emit-macro32`,
   `-emit-vax-object` and `-emit-vax-image` each write their own file and
   combine; `-vax-objects` and `-vax-macro32`, objects the default on
   VMS; `-build` and `-compile` with objects, no MACRO; `-g` links
   `/DEBUG` (`vax-build-objects`). **6b done** (section 17.4):
   `-library` with objects, each module's `.obj` in the library,
   `UNIVERSAL=` from the encoded image, the manifest's `objects`,
   `-install-library` copying objects whole (`vax-library`). **6c done**
   (section 17.5): a cross-built object converts itself in its
   procedure; the base kit builds `OBJCONVERT.EXE` and `SETUP.COM`
   defines `OBJCONVERT` (`check-vax-kit`). **6d done** (section 17.6):
   58 VAX fixtures and `make test-vax` build and run both ways, and
   `make check` runs both; a real numeral exactly halfway is spelt so
   that MACRO rounds it as the front end does. **6e done** (section
   17.7): poc on VMS builds from objects in `make test-vax-guest-poc`
   (each object compared, by its `DUMP/RECORDS`, with the one
   `-vax-objects` writes here) and `vax-poc` (`Sums`); chapter 16 of
   the VAX/VMS Guide starts from poc's objects (`doc-vax-guide`), and
   the libraries chapter, poc(1) and the Reference Guide name the
   objects way. **Step 6 done** (2026-10-20). Every earlier phase's
   VAX fixtures run in both modes - built through `.mar` and `MACRO`, and
   built directly - and give the same output; Phase 17's object libraries
   (`LIBRARY/CREATE` of poc's `.OBJ` files) and shareable images
   (`LINK/SHAREABLE`) work with the direct objects unchanged, and are tested
   that way.

7. **Bootstrap again, and the exit gate.** Rebuild poc for VAX/VMS with
   the direct writer, on the guest: the V1/V2/V3 fixed point of Phase 16
   step 6, now over `.OBJ` files - an object compiled by the poc built from
   the previous stage must be byte-identical to the one the stage before
   produced from the same source (modulo the module header's timestamp
   and the file's creation attributes, which the specification lists). The
   whole VAX conformance suite passes with objects written directly, and
   the whole Phase 17 suite, ASTs included; the run that builds poc must
   involve no `MACRO`.
   The design, proposed 2026-10-20 and approved, is
   `vax-object-language.md` section 18 (pieces 7a-7d). **7a done**
   (section 18.3): `vax-v1 [-vax-macro32 | -vax-objects]`,
   `tools/vax-objects.sh`, the kits built from MACRO-32 by name, and
   `check-vax-kit -full`'s fixed point, broken since 6a, mended.
   **7b done**: `vax-stages [-way objects|macro32]`, objects by default,
   every stage under one `SOURCE_DATE_EPOCH`, `PocRtl.mar` the only
   `MACRO`; both fixed points reached. **7c done**: `vax-guest-poc` and
   `vax-poc` link V1 from its objects. **7d done**: the exit gate, below,
   and this record. **Step 7 done** (2026-10-21).

**Testing summary**: steps 2 and 3 are byte-level comparisons against the
existing text path and against the assembler; steps 4 and 6 are
`ANALYZE/OBJECT` comparisons plus link-and-run; step 7's fixed point
over object files is the gate.


**The exit review** (2026-10-21). The phase's "done", step 7's text,
holds:

- *poc writes the objects MACRO would.* poc's image of every VAX
  fixture's modules (102 `expected-vax.image` files) and of its own 42
  modules for the VAX is MACRO's, byte for byte, on every host (step 3);
  `vax-encoder-forms` covers every instruction and form the fixtures
  miss. Every object poc writes is read back into that image (step 4),
  checked by `ANALYZE/OBJECT` on the guest, and linked: the fixtures
  that build both ways run the program linked from poc's objects and the
  one linked from MACRO's and compare them, and `vax-library` puts
  poc's objects in object libraries and shareable images unchanged.
- *A program can be debugged by its Oberon source.* Every object has
  traceback records, so a fault names each procedure and line; with
  `-g` the 5.5-2 debugger sets breaks by routine and line, steps, shows
  the source, and examines and deposits every variable as its type is
  declared (step 5, `vax-traceback`, `vax-debug-records` and
  `doc-vax-guide` on the guest). What it cannot show, and why, is in
  `vax-object-language.md` section 16.9.
- *poc rebuilds itself from its own objects, with no `MACRO` for its
  modules.* `make vax-stages` reached V1 = V2 = V3 over `.OBJ` files,
  each compared record by record (`DUMP/RECORDS`), the source file
  record by name alone and nothing else masked, every stage under one
  `SOURCE_DATE_EPOCH`: 42 objects and no `.MAR` a stage, and one
  `MACRO`, `PocRtl.mar`'s, in the whole run. On the gate's tree, with
  the guest shared with `check-vax-kit` for its first hour: V1 linked in
  3 seconds, V2 compiled in 54.8 minutes (2991 s of CPU) and linked in
  13 seconds, V3 compiled in 77 minutes (2972 s of CPU; the elapsed time
  is the sharing's), peak virtual memory 204483 pages, 139 minutes in
  all. Run alone in 7b, a stage took 50.7 minutes over objects against
  47.2 over MACRO-32 (`vax-object-language.md`, section 18.3): a
  compilation writing objects takes about a fifth more CPU, and a link
  with no `MACRO` seconds instead of minutes.
- *The whole VAX suite passes with objects, Phase 17's included.* `make
  test-vax` (`tools/vax-suite`, every program built both ways and each
  compared with its LLVM build or its reviewed `expected-vax-*`): 664
  passed, none failed, in 107.5 minutes. `make test-vax-asts`
  (`vax-asts`, `vax-asts-heap`, `vax-conditions-handlers` and
  `vax-subprocesses`, each built both ways and every program run 20 times): all four
  passed, in 16.6 minutes with the guest shared. A full
  `make test-vax-guest-poc` (the fixtures' compilations under poc on the
  guest, V1 linked from its objects, compared with the host's, each
  object by its `DUMP/RECORDS`): all 348 passed, in 102 minutes, the
  guest shared for part of them (84 at Phase 17's close). `make check-vax-kit
  CHECK_VAX_KIT_FLAGS=-full` (the kits, which stay MACRO-32, installed
  as a site would, and the kit's poc compiling its own source to the
  kit's `.mar`): passed, in 117 minutes with the guest shared (58 alone
  in 7a).
- *poc on VMS builds with objects by default.* `-vax-objects` is the
  default on VMS and `-vax-macro32` elsewhere; `-build`, `-compile` and
  `-library` take either; a cross-built object converts itself in its
  build procedure, and the base kit builds `OBJCONVERT` (step 6).

Also found while closing the step:

- *`check-vax-kit -full` had been broken since 6a* (found writing step
  7's design, section 18.1): the kit's poc compiled `[.SRC]` with its
  default on VMS, objects, and the comparison with the kit's `.mar`
  files would have found none. It passes `-vax-macro32` now (7a).

**Left open**, for the phases that follow:

- *Merging `vax-obj` into `main`*, and whether a release follows, is the
  user's call. `main` has two commits since `vax-obj` left it
  (`0f91909`, `make check-o2`, and `95af1c6`); their two bug items are
  recorded below, and `PLAN.md`'s "Ongoing bug fixing" takes this
  branch's text in the merge.
- *Shorter displacements for forward references.* The encoder follows
  MACRO's one-pass rule (section 6.2); relaxing forward references would
  give shorter code and end the byte-for-byte comparison with MACRO.
- *A compilation writing objects takes about a fifth more CPU* than one
  writing MACRO-32 (7b): not looked into.
- *What the debugger cannot show* (section 16.9): a pointer's or a
  procedure variable's value but as an address, a pointer to an open
  array's lengths, a record's dynamic type, the hidden parameters,
  constants wider than a longword, type-bound procedures of one name
  apart, and the program's start by line.
- *The kits stay MACRO-32* by decision (section 18.2, proposal 5): a kit
  is text, and a site rebuilds poc from objects with the kit's poc.

**Exit gate**: `make check` on atla and `tools/check-hosts` on cymoril,
artos and alerik before each commit, with the VAX fixtures against the
guest on atla, both ways since 6d; on the closing tree (`912289a`)
`make vax-stages`, `make check-vax-kit CHECK_VAX_KIT_FLAGS=-full`,
`make test-vax`, `make test-vax-asts` and `make test-vax-guest-poc` on
the guest, as above; rackhir at the close-out, on `2f58055`: 483
fixtures passed, Stage 1 and Stage 2 identical, `check-strict`
(2026-10-21).

## Ongoing bug fixing, during Phase 18

`PLAN.md`'s "Ongoing bug fixing": fixed after Phase 17 closed and
while Phase 18 was current; moved here at the close-out, under its
number there. 8 was fixed on `vax`, which reached `main` in the merge
of 2026-10-17; 9 and 10 on `main` after `vax-obj` left it, whose
fixes reach `vax-obj` with the merge.

8.  **[fixed] An option after the file was ignored.** Found closing
    Phase 17 (2026-10-16): `doc-vax-guide` built `Fail` with `-build
    Fail.Mod -trap-location`, and the trap had no location; among
    `-compile`'s or `-library`'s files an option was read as a file. The
    user, 2026-10-17: poc applies options that come after a file. `Run`
    now applies every option in a first pass, wherever it is, and takes
    the options out before running the command, so a file list holds
    only files; `-help`, the guides and poc(1) say so. Fixture
    `poc-options-after-file`. Fixed on `vax`; it reaches `main` with the
    merge, or by itself if the user wants it there sooner.

9.  **[fixed] poc's own source no longer type-checked under `-O2`.**
    Found 2026-10-18 during Phase 18 step 2a, checking the new
    `VaxInstructions` under `-O2`: `ConstantEvaluator`'s `twoTo32 =
    4294967296`, added with the unsigned integer types (`ff457c2`,
    0.6.0), is wider than a 32-bit `LONGINT`, so under `-O2` every
    expression with it was a `HUGEINT` (12 errors). poc built and worked,
    since every stage builds it under `-OC`, and nothing checked the rule
    (`DEVELOPER.md`, "Rules for poc's own source"), which Phase 15 had
    broken the same way (`phase-16.md`). `twoTo32` is now a variable set
    in the module body, and `make check-o2`, run by `make check` and
    `make check-stage1`, compiles `Poc.Mod` and its imports under `-O2`
    and checks every module of `src/` against them; that check, not a
    fixture, keeps it fixed.

10. **[fixed] `vax-vmsdef` failed in a fresh checkout.** Found
    2026-10-18 gating item 9 in a new checkout of `main`: the fixture
    sends `mlb-listings.com` to the VAX, but `.gitignore`'s
    `test/conformance/**/*.com` (a build procedure poc writes) hid it, so
    it was never committed with Phase 17 step 5 and existed only in the
    checkout every gate had run in. The file is committed now, with an
    exception in `.gitignore`; `vax-vmsdef` passes in the new checkout.

## Ongoing implementation enhancements, during Phase 18

`PLAN.md`'s "Ongoing implementation enhancements": done after Phase 17
closed, on `vax` before its merge into `main` (2026-10-17) and on
`main`, and released in 0.7.0; moved here at the close-out, under its
number there.

5.  **[done] The VAX/VMS Guide in the kit, and `make install-vax`.** Left
    open by Phase 17's exit review; decided with the user 2026-10-17.
    Made on `vax`, since only it has the VAX target. The base kit holds
    the guide as text, `VAX-VMS-GUIDE.TXT` (`tools/doc/plain-text`:
    pandoc, grid tables, ASCII), and `check-vax-kit` checks it unpacked.
    `make install-vax` installs `POCRTL`, `VMSDEF` and `VMSLIB` for
    `vax-dec-vms` under `-O2` and `-OC` beside `poc-rtl`, where poc
    finds them with no `-import-path`, the two kits in
    `DATADIR/peaseblossom/vax`, and the guide as text, HTML and PDF in
    `DOCDIR`; not `rtl/vax`'s source. `make uninstall-vax` removes them
    by the libraries' manifests; `make check-install-vax` (no guest)
    installs both into a scratch directory and builds programs for the
    VAX with that poc alone (`test/install/check-vax.sh`). The
    `peaseblossom-vax` packages come with the packaging work, now that
    `vax` is merged (2026-10-17).

6.  **[done] poc says when the VAX runtime is not installed.** The user,
    2026-10-17, the first of the packaging work. For `-target
    vax-dec-vms`, a module missing when the library path has no `POCRTL`
    for the target and size model, and the import path no `Out.Mod`,
    gets two notes, once a run: that the VAX runtime is not installed,
    and that the `peaseblossom-vax` package or `make install-vax`
    installs it, or `rtl/vax`'s source with `-import-path` (poc on VMS:
    the kit's `@BUILD`). Fixture `poc-vax-runtime-missing`;
    `check-install-vax` checks that an installed `POCRTL` gives no note.

7.  **[done] The `peaseblossom-vax` packages.** Decided with the user
    2026-10-17: a subpackage of the Fedora spec (`noarch`) and of the
    OpenBSD port (`-vax`, `PKG_ARCH = *`), and a port of its own,
    `lang/peaseblossom-vax`, for FreeBSD (`NO_ARCH`) and pkgsrc, which
    shares `lang/peaseblossom`'s `distinfo` and builds poc from the seed
    again. Each needs `peaseblossom` of its own version, and installs
    what `make install-vax` does, its guide in
    `share/doc/peaseblossom-vax` (`VAXDOCDIR`). `make dist` puts the
    guide as text in the tarball (`doc/text`), and `install-vax` takes
    it and the kits from the tarball when they are there, so a package
    builds only the libraries (`installable-vax`), with no pandoc;
    `distcheck` runs `check-install-vax` in the tarball, pandoc out of
    reach. From a git checkout without pandoc (the BSD hosts),
    `check-install-vax` leaves the guide out of the kits and the install
    (`VAX_GUIDE=no`, kits in `build/stage2/vax-kit-without-guide`) and
    says so (2026-10-17). `set-version` and `release-files` know the new packages
    (`DEVELOPER.md`, section 7). Built and checked on each system with
    the first release that has them, 0.7.0 ("Peaseblossom 0.7.0").
