# rtl/vax/vmslib

Hand-written Oberon modules over the VMS interfaces that `tools/sdloberon`
generates into `rtl/vax/vms` (`PLAN.md` Phase 17 step 5;
`doc/developer/vms-sdl-interfaces.md`, part 4). They make the library
`VMSLIB`, which needs `VMSDEF` (`rtl/vax/vms`) and `POCRTL` (`rtl/vax`):

    poc -target vax-dec-vms -library-path <libs> -library VMSLIB rtl/vax/vmslib/*.Mod

They are VAX only, so the Reference Guide's runtime chapter, which is
`rtl/llvm`'s, does not list them. Each procedure that calls VMS returns
VMS's condition value, a `SYSTEM.INT32`. An output string is cut to its
array less one character and ends with `0X`; an input string is passed
up to its `0X`. Fixture `vax-vmslib` runs them on the guest.

- `Conditions.Mod`: a condition value's parts, `Succeeded`, `Severity`,
  `Facility` and `MessageNumber`; the severities `Warning`, `Success`,
  `Error`, `Informational` and `Severe`; `Message`, its text by
  `$GETMSG` ("%SYSTEM-F-ABORT, abort"); `Signal` and `Stop`, by
  `LIB$SIGNAL` and `LIB$STOP`, and `SignalWith` and `StopWith`, with one
  FAO argument. A poc program has no condition handler of its own, so
  VMS's prints a signalled message and a traceback to `SYS$ERROR` and
  goes on, unless the condition is severe. `Stop` never returns.
- `LogicalNames.Mod`: `Define`, `Deassign`, `Translate` and
  `TranslateAt`, in a named table (`Process`, `Job`, `Group`, `System`,
  `FileDevice`) and access mode (`User`, `Supervisor`, `Executive`,
  `Kernel`). A `Supervisor` name is made and deleted by
  `LIB$SET_LOGICAL` and `LIB$DELETE_LOGICAL`, as `DEFINE` and `DEASSIGN`
  do, and outlives the program; any other mode is `$CRELNM`'s and
  `$DELLNM`'s, and without `SYSNAM` a user-mode name, gone when the
  program ends. Translation ignores case.
- `Symbols.Mod`: `Get`, `Set` and `Delete` a DCL symbol, `Local` or
  `Global`, by `LIB$GET_SYMBOL`, `LIB$SET_SYMBOL` and
  `LIB$DELETE_SYMBOL`. A symbol is a string here.
