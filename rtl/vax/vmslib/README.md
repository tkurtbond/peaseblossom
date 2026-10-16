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

- `CommandLanguage.Mod`: a command line parsed by DCL with a command
  table, and its verb, parameters, qualifiers and keywords asked for by
  name: `Presence`, `IsPresent`, `GetValue`, `GetVerb` and `GetLine`, by
  `CLI$PRESENT` and `CLI$GET_VALUE`, for a program run as a verb `SET
  COMMAND` defined. A program with its own table, a `.cld` file given to
  `poc -build`, parses with `Parse`, `ParsePrompting` (by `LIB$GET_INPUT`)
  or `ParseForeign` (its foreign command line), passing the table's
  address, and `RestoreParse` brings back DCL's parse; `HasInterpreter`
  says whether the process has a CLI at all
  (`doc/developer/vax-macro32-backend.md`, section 23). Fixtures
  `vax-cli-verb` and `vax-cli-table` run it.
- `Conditions.Mod`: a condition value's parts, `Succeeded`, `Severity`,
  `Facility` and `MessageNumber`; the severities `Warning`, `Success`,
  `Error`, `Informational` and `Severe`; `Message`, its text by
  `$GETMSG` ("%SYSTEM-F-ABORT, abort"); `Signal` and `Stop`, by
  `LIB$SIGNAL` and `LIB$STOP`, and `SignalWith` and `StopWith`, with one
  FAO argument; `SignalList` and `StopList`, with a whole list in an
  array, any number of FAO arguments and chained conditions, through
  `LIB$CALLG` (`vms-sdl-interfaces.md`, part 5). A poc program has no condition handler of its own, so
  VMS's prints a signalled message and a traceback to `SYS$ERROR` and
  goes on, unless the condition is severe. `Stop` never returns. A
  procedure establishes a `Handler` for its own frame by `Establish`
  (`LIB$ESTABLISH` itself) and removes it by `Revert`. A handler returns
  `Continue` or `Resignal`, or calls `Unwind` to make its establisher
  return, and while an unwind passes, each frame's handler is called with
  `Unwinding`. Fixture `vax-conditions-handlers` runs them.
- `DecimalStrings.Mod`: a `Decimal` of up to 255 digits as `STR$` gives
  one (sign, exponent, digits); `Add`, `Subtract`, `Multiply`, `Divide`,
  `Reciprocal` and `Round`, which return `STR$`'s status, a signal
  included (`LIB$SIG_TO_RET`), so not for AST routines; `FromText`,
  `FromInteger` and `ToText`. Fixture `vax-decimal-strings`
  (`doc/developer/vms-sdl-interfaces.md`, part 9).
- `EventFlags.Mod`: a local event flag got by `Get` (`LIB$GET_EF`) and
  given back by `Free`; `Set`, `Clear`, `IsSet`, `Wait` and `WaitAny`.
- `ExitHandlers.Mod`: `Declare`, a `Handler` called with the exit status
  when the program exits, last declared first, before poc's own. Changing
  the status changes nothing; a handler that calls `$EXIT` ends the
  program there, and the handlers not yet called, poc's own among them,
  are not.
- `LogicalNames.Mod`: `Define`, `Deassign`, `Translate` and
  `TranslateAt`, in a named table (`Process`, `Job`, `Group`, `System`,
  `FileDevice`) and access mode (`User`, `Supervisor`, `Executive`,
  `Kernel`). A `Supervisor` name is made and deleted by
  `LIB$SET_LOGICAL` and `LIB$DELETE_LOGICAL`, as `DEFINE` and `DEASSIGN`
  do, and outlives the program; any other mode is `$CRELNM`'s and
  `$DELLNM`'s, and without `SYSNAM` a user-mode name, gone when the
  program ends. Translation ignores case.
- `SortMerge.Mod`: the constants SORT defines as universal symbols of
  `SORTSHR`, in no SDL module: its options (`stable`, `noDuplicates` ...),
  sort processes and `SOR$STAT`'s statistic codes, checked against the
  linker by fixture `vax-sort`; a key's `ascending` and `descending`; and
  `AddKey`, which fills `SOR$BEGIN_SORT`'s key buffer. The routines are
  `SOR_ROUTINES`' (`doc/developer/vms-sdl-interfaces.md`, part 8).
- `Symbols.Mod`: `Get`, `Set` and `Delete` a DCL symbol, `Local` or
  `Global`, by `LIB$GET_SYMBOL`, `LIB$SET_SYMBOL` and
  `LIB$DELETE_SYMBOL`. A symbol is a string here.
- `Timers.Mod`: `After`, an `AsynchronousTraps.Routine` called at AST
  level with its parameter after a number of milliseconds (`$SETIMR`);
  `Cancel`, by that parameter (`$CANTIM`); and `Sleep` (`$SCHDWK` and
  `$HIBER`). Fixture `vax-asts` runs them, with `EventFlags`.

An AST routine runs at AST level, under `AsynchronousTraps`' rules
(`rtl/vax/AsynchronousTraps.Mod`; `doc/developer/vax-macro32-backend.md`,
section 22).
