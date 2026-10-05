# Bootstrapping with Vishap Oberon

Stage 0 of the bootstrap (`tools/bootstrap/stage0`) builds poc with Vishap
Oberon (voc) 2.1.0, under `-OC`, since poc needs an 8-byte `LONGINT`
(`AGENTS.md`, "How poc itself is built"). Some of voc's bugs reach poc's own
source or its build. This document lists those bugs, what poc does about
each, and where. Keep the workaround when changing the code concerned.

The bugs are written up, with reproducers and a fix for each, in the
separate **vishap-bugs** repository (`~/Repos/Oberon/vishap-bugs`), which
holds every voc bug found while working on poc. "vishap-bugs 13" below
means its issue 13, `issues/13-*.md`, whose fix is `patches/0013-*.patch`.
Elsewhere in poc's source, tests and documentation, a note that voc does
otherwise than poc cites the same numbers. The phase records in
`doc/history/phases/` and `doc/history/phase-11-inventory.md` still point to
`doc/voc-bugs/`, which was here until 2026-10-03; its contents are now in
vishap-bugs (the two long accounts in its `notes/`).

## In poc's source

### A procedure calling itself inside a WITH on its own parameter (vishap-bugs 13)

voc misjudges a call from inside `WITH v: T DO` to the procedure whose
parameter `v` is: it checks the argument against the narrowed type `T`
rather than the declared one, so `P(v.field)` is "incompatible assignment"
(err 113), and passing `v` itself gives C that the C compiler rejects.

**Workaround.** Never call the procedure itself from inside one of its
own `WITH` branches. Either save what the recursive call needs in a local
variable inside the branch and make the call after the `WITH` ends, or call
a differently named procedure from the branch (calling another procedure is
fine), or use type tests (`IS`) instead of a `WITH`. Used in
`SemanticActions` (`ResolveType`, `CheckExpr`, and a walker that uses type
tests), `MemoryLayout` (`Size` and `NaturalAlign`), `NestedProcedures` (its
walkers), and `LLVMCodeGenerator` (`CollectRecordTypes`, and the
`child1`/`child2` variables of the expression walk).

### Integral LONGREAL literals of 2^31 or more (vishap-bugs 01)

voc stops with `Halt(-8)`, "Value out of range", on a `LONGREAL` literal
whose value is integral and at least 2^31 (`2147483648.0D0`, `1.0D10`),
and on a constant `ENTIER` of such a value.

**Workaround.** Build such a number by arithmetic: `LLVMCodeGenerator.
DoubleBitsText` makes 2^52 by doubling 1.0D0 52 times.

### REAL literals with exponent 38, LONGREAL with 308 (vishap-bugs 04)

voc rejects `1.0E38`..`MAX(REAL)` and `1.0D308`..`MAX(LONGREAL)` as "number
too large", though both are in range.

**Workaround.** `ConstantEvaluator.PowerOfTwo` builds the largest finite
values from powers of two.

### LONG(SHORT(x)) is folded to x (vishap-bugs 06)

voc does not round `SHORT(x)` of a `LONGREAL` to `REAL` inside an
expression, only where it is stored, so `LONG(SHORT(x))` is `x`.

**Workaround.** Round through a `REAL` variable: `ConstantEvaluator.
RoundToSingle` and `LLVMCodeGenerator.RealConstant` (`rounded :=
SHORT(folded); folded := rounded`).

### 64-bit DIV and MOD near MIN(LONGINT) (vishap-bugs 07)

voc's run-time `DIV` and `MOD` overflow for a dividend within the divisor
of `MIN(LONGINT)` (`MIN(LONGINT) DIV 2` is positive), and its constant
folder therefore rejects `(-4611686018427387904) * 2`.

**Workaround.** Never divide such a value: `ConstantEvaluator.
FloorQuotient`/`FloorRemainder` divide a negative `x` as `-(-(x + 1) DIV
y) - 1`, `ProductOverflows` checks a product with no negative dividend,
and `ModuleInterface.FormatInt` writes digits without dividing a value
near the minimum.

## In voc's library, as poc uses it

### Files keeps names relative to the directory current at New and Old (vishap-bugs 15)

voc's `Files` stores a file's name as given and, when the same file is
registered again, renames the open `File` by that name from whatever
directory is current then. If that is another one, it stops with
"Couldn't rename previous version of file being registered" and
`Halt(99)`. (Its `Files.New` also halts on a missing directory.) Stage 0
hit it now and then in `test/conformance/llvm-libraries`, depending on the
collector's timing.

**Workaround.** poc never changes directory around a file operation and
makes every file by its whole path. `ModuleInterface.Write` and
`LLVMToolchainDriver.EmitIR` check that the output directory exists with
`Platform.Chdir` and change straight back.

### Files.Delete of a file the program has open (vishap-bugs 16)

voc renames an open file to a temporary name before deleting it, so
`Files.Delete` reports failure.

**Workaround.** `LLVMToolchainDriver` removes a stale `.ll` with
`Platform.Unlink`, not `Files.Delete`.

## In voc's runtime

### The collector misses a pointer held only in a callee-saved register (vishap-bugs 14)

voc compiles its C without optimization, so `Heap.GC`'s way of getting the
callee-saved registers onto the stack does nothing, and a pointer that the
C compiler keeps only in one of them is not a root: its block is freed
while in use. `notes/14-gc-callee-saved-registers/` in vishap-bugs has the
analysis and the results per host.

**Workaround.** `tools/bootstrap/stage0` links poc with
`tools/bootstrap/voc-heap-gc-spill.c`, a `Heap_GC` that stores the
callee-saved registers in its own frame (`__builtin_unwind_init`) and then
calls libvoc's; the dynamic linker binds libvoc's own calls of `Heap_GC` to
it too. Stage 0 checks with `nm` that poc was linked with it. poc's own
collector (`rtl/llvm/GarbageCollectedHeap.Mod`) does the same with
`llvm.eh.unwind.init`.
