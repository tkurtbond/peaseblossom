# rtl/vax

poc's runtime for the VAX/VMS target (`PLAN.md` Phase 16), in Oberon-2
over a thin MACRO-32 layer (`doc/developer/vax-macro32-backend.md`,
section 15). There are no VMS libraries yet (Phase 17), so a program
finds these modules as source: `poc -target vax-dec-vms -import-path
<this directory> -build ...` compiles the ones it imports with it and
writes their `.mar` files.

- `PocRtl.mar`, MACRO-32, which a program poc builds for `vax-dec-vms`
  links as `POCRTL.OBJ`. Its `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and
  `POC_HMOD` are the final routines. `POC_TRAP` writes the trap's
  message to `SYS$ERROR` and exits with the trap's status, and
  `POC_HALT` exits with `HALT`'s (section 14, item 10). `POC_NEW`
  allocates from `LIB$GET_VM` and never frees, until step 4 ports the
  collector (section 15, proposal 9). The rest are what the modules
  below call: writing records to `SYS$OUTPUT` and `SYS$ERROR`, logical
  names, `$ERASE`, `$PARSE`, `LIB$CREATE_DIR`, `$SETDDIR`, `$GETJPI`
  and `LIB$GET_FOREIGN`.
- `Out.Mod` and `Err.Mod` (`Open`, `Flush`, `Char`, `String`, `Ln`,
  `Int`, `Hex`) write to `SYS$OUTPUT` and `SYS$ERROR` through
  `LineOutput.Mod`, a record for each `Ln` (section 14, item 2, and
  section 15, proposal 8).
- `Modules.Mod` (`ArgCount`, `GetArg`): the command line of a foreign
  command, split as DCL quotes it (section 15, proposal 6).
- `Platform.Mod` (`GetEnv`, `Unlink`, `System`, `Exit`, `PID`, `CWD`,
  `NL`): logical names, files by name, and ending the process (section
  15, proposals 3 and 5 to 8).
- `Directories.Mod` (`pathSeparator`, `MakePath`, `IsDirectory`,
  `MakeDirectory`): directories, and the names of the files in them, as
  VMS writes them (section 15, proposal 4).

`Files` and the collector are still to come (section 15, proposal 10).
