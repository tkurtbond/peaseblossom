# rtl/vax

poc's runtime for the VAX/VMS target (`PLAN.md` Phase 16), in Oberon-2
over a thin MACRO-32 layer (`doc/developer/vax-macro32-backend.md`,
section 15). A program finds these modules as source, `poc -target
vax-dec-vms -import-path <this directory> -build ...` compiling the ones
it imports with it, or in the library `POCRTL` (Phase 17 step 1,
section 18), made by `poc -target vax-dec-vms -library POCRTL
rtl/vax/*.Mod rtl/vax/PocRtl.mar`. Which of `rtl/llvm`'s modules are to
come, and what each needs, is in `doc/research/vms-module-inventory.md`.

- `PocRtl.mar`, MACRO-32, which a program poc builds for `vax-dec-vms`
  links as `POCRTL.OBJ`. Its `POC_STRCMP`, `POC_HMUL`, `POC_HDIV` and
  `POC_HMOD` are the final routines. `POC_TRAP` writes the trap's
  message to `SYS$ERROR` and exits with the trap's status, and
  `POC_HALT` exits with `HALT`'s (section 14, item 10). `POC_ROOTS`
  lists each module's root table, in every program. The rest are what
  the modules below call: writing records to `SYS$OUTPUT` and
  `SYS$ERROR`, logical names, `$ERASE`, `$PARSE`, `LIB$CREATE_DIR`,
  `$SETDDIR`, `$GETJPI`, `LIB$GET_FOREIGN`, RMS file access for
  `Files`, and memory, saved registers, an exit handler and the paging
  file quota for the collector.
- `Out.Mod` and `Err.Mod` (`Open`, `Flush`, `Char`, `String`, `Ln`,
  `Int`, `Hex`) write to `SYS$OUTPUT` and `SYS$ERROR` through
  `LineOutput.Mod`, a record for each `Ln` (section 14, item 2, and
  section 15, proposal 8).
- `Modules.Mod` (`ArgCount`, `GetArg`, `GetIntArg`, `ArgPos`): the
  command line of a foreign command, split as DCL quotes it (section 15,
  proposal 6; section 16, proposal 6).
- `Console.Mod` (`Flush`, `Char`, `String`, `Ln`, `Bool`, `Int`, `Hex`):
  `rtl/llvm`'s `Console`, writing to `SYS$OUTPUT` through
  `LineOutput.Mod` into the same line as `Out` (section 16, proposal 6).
- `Platform.Mod`: voc's and `rtl/llvm`'s whole interface (section 19.1,
  Phase 17 step 3): files by handle in a table of 32 (Stream_LF ones by
  block I/O, others read a record at a time with an LF after each),
  identities and revision dates, the clock, logical names, the default
  directory, a command in a subprocess (`LIB$SPAWN`), memory, and the
  error tests over RMS and system-service statuses; `StdOut` and
  `StdErr` go through `LineOutput`. Earlier, `GetEnv`, `Unlink`,
  `System` and `Exit` (section 15, proposals 3 and 5 to 8).
- `Directories.Mod` (`pathSeparator`, `MakePath`, `MakeSubdirectory`,
  `NameStart`, `IsDirectory`, `MakeDirectory`, and `Search`,
  `StartSearch`, `NextFile` for wildcards): directories, and the names
  of the files in them, as VMS writes them (section 15, proposal 4;
  section 18.5).

- `Files.Mod` (`File`, `Rider`, `Old`, `New`, `Register`, `Close`,
  `Length`, `Set`, `Base`, `Read`, `Write`, `ReadString`, `ReadLine`,
  `WriteString`, `Delete`): the files poc makes are Stream_LF, written
  and read by block I/O; a file of another record format is read a
  record at a time, an LF after each (section 15, proposal 2).
- `GarbageCollectedHeap.Mod` (`Allocate`, `Collect`, `SetStackBase`,
  `SetHeapLimit`, `SetChunkSize`, `SetMarkStackCapacity`,
  `CollectionCount`, `HeapBytes`, `LiveBytes`, `IsAllocated`,
  `RegisterFinalizer`, `FinalizeAll`): `rtl/llvm`'s collector, which
  `NEW` allocates from; `-build` adds it to a program that calls `NEW`.
  Its heap stops at three quarters of the paging file quota left when it
  starts (section 15, proposal 9).
