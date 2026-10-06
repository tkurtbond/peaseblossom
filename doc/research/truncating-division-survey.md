# Truncating division and remainder: what other languages do (Phase 19, QUOT and REM)

Written 2026-10-05 for the proposal in
`doc/developer/language-extensions.md`, "QUOT and REM": predeclared
`QUOT(x, y)` and `REM(x, y)`, the integer quotient truncated toward zero
and its remainder, which has the dividend's sign - Ada's `/` and `rem`,
C's `/` and `%`. Oberon's `DIV` and `MOD` floor instead, and poc extends
them to negative divisors (`language-extensions.md`, "Overflow, division
and reals"). The question here is whether any Oberon, or Modula-2 or
Modula-3, which came before them, has the truncating pair, and under what
name. Nothing here changes poc.

Every source is a local file, read on the date above: the reports under
`~/Reference/Computer/Languages/`, and the compilers' sources under
`/usr/local/sw/src/lang/Oberon/`.

## 1. The two pairs

Each pair satisfies `x = q * y + r`; they differ in how `q` is rounded,
and so in the sign of `r`, whenever `x` and `y` have different signs and
`y` does not divide `x`:

| x | y | floor `q` (`DIV`) | floor `r` (`MOD`) | truncated `q` | truncated `r` |
|---|---|---|---|---|---|
| 7 | 2 | 3 | 1 | 3 | 1 |
| -7 | 2 | -4 | 1 | -3 | -1 |
| 7 | -2 | -4 | -1 | -3 | 1 |
| -7 | -2 | 3 | -1 | 3 | -1 |

The floor remainder has the divisor's sign; the truncated one the
dividend's. A third pair, Euclidean, keeps the remainder never negative
(PIM4's `MOD`, below).

## 2. The Oberon family

**The reports.** None has a truncating quotient or a remainder:
`MulOperator` is `"*" | "/" | DIV | MOD | "&"` in each.

| Source | `DIV` and `MOD` |
|---|---|
| `Oberon2.pdf` §8.2.2 | "defined for any x and positive divisors y": `x = (x DIV y) * y + (x MOD y)`, `0 ≤ (x MOD y) < y`. A negative divisor is outside the definition. |
| `Oberon.Report.pdf` (1990) | The same two formulas. |
| `Oberon-2012/Oberon07.Report.pdf` | "quotient q and remainder r are defined by the equation `x = q*y + r`, `0 <= r < y`" - again only satisfiable for `y > 0`. |
| `Oberon-2-2020/The-Revised-Oberon2-Programming-Language.pdf` | Describes only its additions to Oberon-07; none to `DIV` or `MOD`. |
| `Component-Pascal-Report.pdf` §8.2.2 | Floor for either sign: `0 <= (x MOD y) < y` or `0 >= (x MOD y) > y`, and "`x DIV y = ENTIER(x/y)`"; `5 DIV -3` is -2, `5 MOD -3` is -1. |
| `Active-OberonLanguageReport.pdf` §10.4 | `MulOp = '∗' | '/' | 'DIV' | 'MOD' | '&'`. §10.3.1 tells of a production assertion, `assert(−1 MOD 3 = −1)`, that held only while unary minus bound looser than `MOD`: "In fact, (−1) MOD 3 = 2!" - someone expected a remainder and had a modulus. |
| `oakwood-guidelines.pdf` §5.10 | Notes that `-5 MOD 3` is `-(5 MOD 3)`; nothing else on division. |
| Oberon+ (`OberonPlus/specification`, last commit 2026-08-24) | The Oberon-2 report's text: positive divisors only. |

**The compilers.** No compiler has `REM`, `QUOT` or a truncating operator
as a name the language knows; searched for in each scanner and table of
predeclared names: voc (`vishap`), Ofront, OfrontPlus, oo2c, obc, OBNC,
A2 (`oberon-a2`, `AOS`), BlackBox (`bbcp`), Linz Oberon V4, Native Oberon
3 and Oberon+. Nor does any standard library export a procedure for it
(searched for exported `Rem`, `Quot`, `Quotient`, `Remainder`, `IntDiv`,
`TruncDiv`, `DivMod`, `QuoRem` and the like). The only hits are beside
the point: oo2c's `Object/BigInt` has a private `DivRem` under its exported
`DivMod` (floor, like `DIV`), and A2's `Oberon.Scheme` has `Quotient` and
`Remainder` for the Scheme it interprets.

So in the Oberon family a program that wants Ada's or C's division writes
it out from `DIV`, `MOD` and the signs of its operands, and can get that
wrong as easily as Active Oberon's assertion did.

## 3. Modula-2

Modula-2 changed its mind twice, which GNU Modula-2's manual calls "the
most dangerous set of mutually exclusive features found in the four
dialects" (`Modula-2/gm2-15.pdf`, §2.6.1, "Integer division, remainder and
modulus"). Its table, with -31 and 10:

| x | y | PIM2/3 `DIV` | PIM2/3 `MOD` | PIM4 `DIV` | PIM4 `MOD` | ISO `DIV` | ISO `MOD` | ISO `/` | ISO `REM` |
|---|---|---|---|---|---|---|---|---|---|
| 31 | 10 | 3 | 1 | 3 | 1 | 3 | 1 | 3 | 1 |
| -31 | 10 | -3 | -1 | -4 | 9 | -4 | 9 | -3 | -1 |
| 31 | -10 | -3 | 1 | -3 | 1 | exception | exception | -3 | 1 |
| -31 | -10 | 3 | -1 | 4 | 9 | exception | exception | 3 | -1 |

- **PIM2 and PIM3**: `DIV` truncates, and `MOD` is its remainder, with the
  dividend's sign - Ada's `/` and `rem` under Oberon's names.
- **PIM4**: `MOD` is never negative, and `DIV` goes with it (Euclidean
  division). The 1988 report printed in *Programming in Modula-2*, 4th
  edition (`Modula-2-Report-from-PIM2-4E-1988_...pdf`), says "x DIV y is
  equal to the truncated quotient of x/y ... x MOD y is equal to the
  remainder of the division x DIV y ... 0 <= (x MOD y) < y", which cannot
  all hold for a negative `x`; gm2 takes the last rule.
- **ISO Modula-2** (ISO/IEC 10514-1, 1996; p. 201 per gm2): both pairs.
  `DIV` and `MOD` floor, defined for a positive divisor only (a negative
  one raises an exception); and **`/` on integers truncates, with `REM`
  its remainder, of the dividend's sign**. `REM` is a reserved word and a
  `MulOperator` (gm2's grammar: `... | 'REM' | 'AND' | '&'`). This is the
  one precedent for the proposal, under the names `/` and `REM`.
- gm2 itself implements ISO's `DIV` and `MOD` for a negative divisor as
  PIM4's, not with the exception ("a temporary implementation situation").

## 4. Modula-3

`Modula-3/Modula-3_Language_Definition.pdf` and `M3.html`, §2.6.10: "The
value x DIV y is the floor of the quotient of x and y ... For integers x
and y, the value of x MOD y is defined to be x - y * (x DIV y). This means
that for positive y, the value of x MOD y lies in the interval [0 .. y-1],
regardless of the sign of x. For negative y, the value of x MOD y lies in
the interval [y+1 .. 0], regardless of the sign of x." That is exactly
poc's `DIV` and `MOD`. There is no truncating operator; the required
interface `Word` (§9.3) has `Divide` and `Mod`, but for "operations on
unsigned words", where truncating and floor agree. Not
verified: whether a Modula-3 library has a truncating division (no
Modula-3 compiler's source is here).

## 5. Ada, C and LLVM, for comparison

- **Ada** (`Ada/ARM/2022/AA-Final.pdf`, RM 4.5.5): "Signed integer division
  and remainder are defined by the relation `A = (A/B)*B + (A rem B)` where
  `(A rem B)` has the sign of A and an absolute value less than the absolute
  value of B. Signed integer division satisfies the identity `(-A)/B =
  -(A/B) = A/(-B)`." `A mod B` "has the sign of B". So Ada's `mod` is
  Oberon's `MOD`; its `/` and `rem` are the truncated pair; Ada has no floor
  quotient.
- **C** (C99 and later): `/` truncates toward zero, and `%` has the
  dividend's sign (`(a/b)*b + a%b == a`) - Ada's `/` and `rem`.
- **LLVM**: `sdiv` and `srem` are the truncated pair. poc builds `DIV`
  and `MOD` from them with a correction for the floor
  (`LLVMCodeGenerator.Mod`), so `QUOT` and `REM` would each be the one
  instruction.

## 6. What this says for the proposal

1. **No Oberon has it**, in the language or a standard library. It would
   be poc's own, as `HUGEINT`, read-only parameters and record literals
   (in this form) are.
2. **The only precedent is ISO Modula-2**, which spells it `/` and `REM` -
   operators, `REM` reserved. Wirth's own Modula-2 (PIM2/3) had the
   truncated pair under the names `DIV` and `MOD`, and dropped it; Oberon
   kept the names with floor meanings, so those names cannot be reused.
3. **Modula-3**, the other successor, has only the floor pair, as Oberon.
4. Ada and C, the languages programs are ported from, both have the
   truncated pair, and neither has a floor quotient; Ada also has the floor
   remainder (`mod`).

Against the proposal's choices:

- An operator `REM` would follow ISO Modula-2, but a new reserved word
  breaks every program with a `REM` of its own. A predeclared function
  procedure breaks none (a module may declare its own, as with `ASSERT`).
- ISO's truncating quotient is `/`, which Oberon gives only to reals (and
  sets); making `/` of two integers an integer would change the meaning of
  every `i / j` in an Oberon program from `REAL` to integer. So the
  quotient needs a name: `QUOT` is the proposal's (Scheme's `quotient`,
  Haskell's `quot`, which also has `rem`).
