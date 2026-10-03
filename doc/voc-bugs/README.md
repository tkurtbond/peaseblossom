# Known voc bugs

Bugs (not deviations from the report) found in voc 2.1.0 while building
poc with it and while cross-checking poc against it. Each entry says
where poc meets it, or where poc does otherwise. Moved here from
`AGENTS.md` (2026-09-25), which keeps a one-line list of the compiler's;
extended on 2026-10-02 from the compiler bugs that affect poc's own
source to every voc bug met so far. A directory beside this file has the
full write-up and reproducers for one: `with-self-recursion/` and
`gc-callee-saved-registers/`.

## The compiler

Worth knowing before puzzling over a bogus-looking error during Stage
0/1/2 bootstrapping:

- **Self-recursive call from inside a `WITH` branch, misdiagnosed as
  "incompatible assignment"**: if procedure `P` calls itself from inside
  one of `P`'s own `WITH v: T DO ... END` branches, voc rejects the call
  even when the argument's type is fine — reproduced with a minimal
  `POINTER`/`WITH`/self-call example (not just in poc's own source).
  Calling a *different* procedure from inside the same `WITH` branch is
  unaffected; only literal self-recursion from inside one's own `WITH`
  triggers it. Workaround: save whatever the recursive call needs into a
  local variable inside the `WITH` branch, then make the recursive call
  after the `WITH` statement ends. See
  `src/front/SemanticActions.Mod`'s `ResolveType` for a real instance.

- **`LONGREAL` literal rejected with "Value out of range"**: a `LONGREAL`
  literal whose value is integral and at least 2^31 fails to compile —
  `2147483648.0D0`, `1.0D10`, `4.5D15` all fail; `2147483647.0D0`,
  `1.0D38`, `1.0D300` and any non-integral value compile. Workaround:
  build the number arithmetically (see `LLVMCodeGenerator.DoubleBitsText`'s
  `twoTo52` loop).
- **A `REAL` literal with decimal exponent 38, or a `LONGREAL` one with
  exponent 308, is rejected as "number too large"**, though both are within
  what the type holds: `1.0E38`, `1.5E38`, `3.4E38`, `1.0D308`, `1.7D308`
  fail; `9.9E37`, `1.0D300` compile. There is no way to write a value near
  `MAX(REAL)`/`MAX(LONGREAL)` as a literal - `llvm-ash-max-min` compares
  against `1.0D300`-sized numbers instead (found while writing it).
- **`LONG(SHORT(x))` folded away**: voc simplifies that chain to `x`,
  skipping the narrowing to single precision it exists for. Assign
  through a `REAL` variable instead (see `LLVMCodeGenerator.RealConstant`).
- **Lossy real constants in generated C**: voc prints each `REAL`
  constant with 8 significant digits and each `LONGREAL` one with 15
  (`1.0000000e-001`, `1.00000001490116e-001`), so a constant that needs
  more digits to round-trip reads back as a different value in the C
  compiler. Only matters when cross-checking poc's output against voc's:
  three of `test/conformance/llvm-reals`'s checks fail under voc for
  this reason and pass under poc.
- **`DIV`/`MOD` overflow near `MIN(LONGINT)`**: with a 64-bit `LONGINT`
  (`-OC`), voc's generated `DIV`/`MOD` of a negative dividend within the
  divisor of the minimum give wrong, positive results - `MIN(LONGINT) DIV 2`
  is 4611686018427387903 and `(MIN(LONGINT) + 1) DIV 2` positive too. poc is
  built with voc, so `ConstantEvaluator` never divides such a value
  (`FloorQuotient`/`FloorRemainder`, `ProductOverflows`). voc's own constant
  folder seems to suffer the same way: it rejects the product
  `(-4611686018427387904) * 2` (exactly -2^63, which fits), and its compiler
  dies of SIGFPE folding `MIN(HUGEINT) DIV (-1)`.
- **`CAP` of a character that is not a lower-case letter is masked**: voc's
  `CAP(x)` is C's `x & 0x5F`, so `CAP("7")` is 17X and `CAP("{")` is `[`, in a
  `CONST` and at run time alike. The report defines `CAP` only for letters;
  poc's, folded or generated, changes a lower-case letter and leaves anything
  else as it is (`test/conformance/llvm-const-value-functions`).
- **A row of a multi-dimensional open array passed on as an open array
  ignores the row stride**: with `a: ARRAY OF ARRAY OF INTEGER`,
  `Sum(a[r])` (a call whose parameter is `VAR ARRAY OF INTEGER`) makes voc
  pass `&a[r]` as if `a` were one-dimensional, so it hands over elements
  `r`..`r+n-1` of the flat data instead of row `r` - `Sum(grid[2])` on a
  fixed array is right, `RowSum(grid, 2)` inside a procedure is not. poc
  computes the stride (`test/conformance/llvm-open-array-params` check 8
  is the one check voc gets wrong).
- **A nested procedure sees garbage for the inner lengths of an enclosing
  procedure's multi-dimensional open array** (found 2026-09-25, Phase 11
  A17): voc copies an enclosing procedure's parameters into a frame record
  for its nested procedures, and for `x: ARRAY OF ARRAY OF INTEGER` writes
  `_s.x__len = x__len; _s.x__len = x__len;` - the outer length twice, never
  `x__len1` - so in the nested procedure `LEN(x, 1)` and every `x[i, j]`
  use an uninitialized length. `RETURN x[0, 0] + LEN(x, 1)` from a nested
  procedure gave -15331 (2 dimensions) and 4917 (3) where poc gives 7; one
  dimension is right; with 9 it stopped with a NIL access. poc passes each
  length as its own hidden parameter (`test/conformance/
  llvm-open-array-many-dimensions`, whose "nested" lines are the only ones
  not compared with voc).
- **A constant `ENTIER` out of range kills the compiler**: under `-OC`,
  folding `ENTIER(3000000000.5D0)` stops voc with `Halt(-8)`, and past
  2^63 it says "number too large". poc makes an `ENTIER` that does not
  fit the model's `LONGINT` a compile-time error (`ConstantEvaluator`;
  `test/conformance/semantic-const-value-functions`; Phase 11).

## The runtime

- **The collector frees an object whose only reference is in a
  callee-saved register** (found 2026-10-02 in another project,
  `gc-callee-saved-registers/`): voc compiles its C without optimization,
  so `Heap.GC`'s "register pressure" locals spill nothing, and a pointer
  that gcc keeps in `rbx` or `r12`-`r15` while it evaluates a call whose
  arguments allocate (`Check(Make("a"), Make("b"))`) is not a root. The
  reproducer corrupts 752 of 1,000,000 calls under voc and none under
  poc, whose `GarbageCollectedHeap.Collect` spills the registers first
  (`llvm.eh.unwind.init`). Stage 0, poc as voc builds it, is linked with
  `tools/bootstrap/voc-heap-gc-spill.c`, a `Heap_GC` that spills the
  registers and then calls libvoc's.
- **`Files.Register` over a file whose identity matches a `File` it no
  longer has** (2026-10-02, once, on cymoril, OpenBSD i386): Stage 0
  stopped in `test/conformance/llvm-libraries` with "Couldn't rename
  previous version of file being registered:
  lib/<triple>/O2/ModuleTable.sym, f.fd = 7, errcode = 2" and `Halt(99)`.
  voc's `Deregister` finds the `File` to turn into a temporary one by
  device and inode, and renames it by the name it had; here that name was
  gone (ENOENT). Likely an inode reused for the new file while a stale
  `File` still held the old one's identity, or the collector bug above
  corrupting the list of files; not reproduced in five reruns, and not
  seen with poc's own `Files` (Stage 1 passed the same fixture in the
  same run).
- **`Files.Rename` or `Files.Delete` of a file the program has open**:
  voc renames it to a temporary name first, so `Delete` fails (errcode
  2) and `Rename` halts with the same "Couldn't rename previous version"
  message; `test/conformance/llvm-files` renames and deletes only files
  it has not opened (Phase 10).

## The library modules

Recorded in full in each poc module's header, "Where this differs from
voc's"; poc's module does what the description says. Each was checked
against voc's source or by running it.

- **`Strings`**: `Insert` at a position past the end calls `Append` with
  its arguments the wrong way round, so nothing happens; `Replace`
  deletes `pos + Length(src)` characters, not `Length(src)`; `Append`
  and `Extract` can leave `dst` without its 0X, and `Extract` writes its
  0X past the end of a short `dst` (`llvm-strings-extra`).
- **`Files`**: `ReadString` and `ReadLine` do not stop at the end of the
  array: a longer value is an index trap, or with voc's `-x` off, a
  write past it.
- **`In`**: `Name` stops the program ("Not implemented"); `HugeInt` reads
  hexadecimal digits without an `H` as a garbage decimal number, and
  takes a `SYSTEM.INT64` that a `HUGEINT` variable is not accepted for
  (err 123); `Real`/`LongReal` cut the line to 15 characters and never
  set `Done`.
- **`Out`**: `Int` prints a fixed, wrong string for `MIN(HUGEINT)` (by
  its source, not run); `Real`/`LongReal` are not correctly rounded.
- **`Math`/`MathL`**: `sincos` gives the cosine as `sqrt(1 - sin^2)`,
  never negative; `succ` of a negative number moves down; `pred(1)` is
  not the true predecessor; `ulp(1)` is inexact; `MathL.power(0, 3)`
  fails; `MathL.small` is 0 and `MathL.large` below `MAX(LONGREAL)`;
  `sin`/`cos` give up beyond about 9099 in `Math`; a denormal's
  `exponent` is -127 (`llvm-math-extra`; Phase 10).
- **`Texts`**: a subnormal real is written as 0 and an infinity as
  "NaN"; `WriteRealFix` drops decimals and goes wrong past 9 digits
  before the point; `Scan` stops the program (`HALT(40)`) on a number
  past the type's range.
- **`Reals`**: `TenL` squares its way up and is off in the last bit for
  252 of the exponents 0..308 (`llvm-reals-module`; Phase 12 step 5f).
- **`VT100`**: a count of 10 or more is cut to its first digit
  (`CUU(12)` moves up one line), `DSR(n)` sends 6 whatever `n` is, and
  `SetAttr` cuts its argument at 13 characters (`llvm-vt100`).

## The documentation

- **`doc/Features.md` says `SET` is 64 bits under `-OC`**; `OPM.Mod`
  makes it 4 bytes under both size models, and poc follows the source
  (`AGENTS.md`, "Size models").
