# rtl/vax

poc's runtime for the VAX/VMS target (`PLAN.md` Phase 16). So far it is
one MACRO-32 module, `PocRtl.mar`, which a program poc builds for
`vax-dec-vms` links as `POCRTL.OBJ`. Its `POC_STRCMP`, `POC_HMUL`,
`POC_HDIV` and `POC_HMOD` are the final routines. `POC_TRAP` and
`POC_HALT` are provisional until step 3c. The rest of the runtime, in
Oberon-2 over a thin MACRO-32 layer, is step 4's
(`doc/developer/vax-macro32-backend.md`, section 13).
