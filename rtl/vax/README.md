# rtl/vax

poc's runtime for the VAX/VMS target (`PLAN.md` Phase 16).

- `PocRtl.mar`, MACRO-32, which a program poc builds for `vax-dec-vms`
  links as `POCRTL.OBJ`. Its `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and
  `POC_HMOD` are the final routines, and so are `POC_PUT_LINE` and
  `POC_OUT_REGISTER`, which `Out` writes through. `POC_NEW` allocates
  from `LIB$GET_VM` and never frees, until step 4 ports the collector
  (`doc/developer/vax-macro32-backend.md`, section 14, item 3).
  `POC_TRAP` writes the trap's message to `SYS$ERROR` and exits with the
  trap's status, and `POC_HALT` exits with `HALT`'s (section 14, item
  10).
- `Out.Mod`, a minimal `Out` (`Open`, `Flush`, `Char`, `String`, `Ln`,
  `Int`, `Hex`), pulled forward from step 4 so that step 3's fixtures can
  print (`doc/developer/vax-macro32-backend.md`, section 14, item 2). There
  are no VMS libraries yet (Phase 17), so a program finds it as source:
  `poc -target vax-dec-vms -import-path <this directory> -build ...`
  compiles it with the program and writes `Out.mar`.

The rest of the runtime, in Oberon-2 over a thin MACRO-32 layer, is step
4's (section 15).
