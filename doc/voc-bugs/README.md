# Known voc bugs affecting poc's own source

Moved here from `AGENTS.md` (2026-09-25), which keeps a one-line list.
`with-self-recursion/` has the full write-up and reproducers for the first one.


Bugs (not spec deviations) found in voc 2.1.0 while writing poc's own
source, worth knowing before puzzling over a bogus-looking error again
during Stage 0/1/2 bootstrapping:

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
