# src/back/vax

The VAX/VMS 5.5-2 backend: MACRO-32 assembly text (`PLAN.md` Phase 15),
then assembling, linking and running it on VMS (Phase 16). The design,
written before any code, is `doc/developer/vax-macro32-backend.md`; its
section 12 is the order of work. `VaxTypes.Mod` has the sizes and the
names, `VaxCodeGenerator.Mod` writes a module's `.mar` as the lines of
`VaxInstructions.Mod` (Phase 18 step 2,
`doc/developer/vax-object-language.md` section 13), and
`VaxToolchainDriver.Mod` writes the file and, for `-build` and
`-compile`, the DCL procedure that assembles and links the modules on VMS
(section 13). Phase 18 (`doc/developer/vax-object-language.md`) adds
the object written directly: `VaxImage.Mod` holds a module as the linker
sees it, `VaxOpcodes.Mod` and `VaxEncoder.Mod` encode the lines into one
(step 3; each procedure's as soon as it is written, and the lines then
dropped unless MACRO-32 is wanted too: `doc/developer/vms-memory.md`,
step 6), and `VaxObjectWriter.Mod` writes its records (step 4) through
`ObjectRecords`, whose two implementations are in `host/`, for poc
built for Linux and the BSDs, and `vms/`, for poc built for VMS, each
chosen by the import path.
