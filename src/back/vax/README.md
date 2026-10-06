# src/back/vax

The VAX/VMS 5.5-2 backend: MACRO-32 assembly text (`PLAN.md` Phase 15),
then assembling, linking and running it on VMS (Phase 16). The design,
written before any code, is `doc/developer/vax-macro32-backend.md`; its
section 12 is the order of work. `VaxTypes.Mod` has the sizes and the
names, `VaxCodeGenerator.Mod` writes a module's `.mar`, and
`VaxToolchainDriver.Mod` is the stub that writes the file.
