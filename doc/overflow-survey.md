# Overflow, underflow and division: what other Oberons do (Phase 11, C5)

Written 2026-09-21 for inventory item C5 ("check that everything that should
raise underflow or overflow does"). `Oberon2.pdf` defines none of this - no
occurrence of "overflow", "underflow" or "undefined" in its text (checked
2026-09-20) - so there is no "should" to check against; this file is the
survey `000-todo.org` asked for before any decision. It says what each source
*does*, marks what could not be verified, and ends with what poc does today
(probed) and a proposal. Nothing here changes poc.

## 1. The questions

1. Integer `+ - *`, unary `-`, `ABS`, `INC`/`DEC` past the type's range: wrap,
   trap, or unchecked/undefined?
2. Integer `DIV`/`MOD` by zero, by a negative divisor, and `MIN DIV -1`.
3. Real overflow, underflow, division by zero and `0.0/0.0`: IEEE
   infinity/NaN silently, or a trap?
4. (Next to them in the Oakwood list of illegal operations) `SHORT`, `CHR` and
   `SET` elements outside their range.

## 2. What the language definitions say

| Source (local file) | Says |
|---|---|
| `Oberon2.pdf`, `Oberon2-Report.pdf` | Nothing on overflow or underflow. `DIV`/`MOD` "defined for any x and positive divisors y" (§8.2.2), so a zero or negative divisor is outside the definition. |
| `Oberon.Report.pdf` (1990 original) | Nothing on overflow. |
| `Oberon-2012/Oberon07.Report.pdf` | Nothing on overflow. `x = q*y + r, 0 <= r < y` - again only satisfiable for `y > 0`. |
| `oakwood-guidelines.pdf` §2.3 | "Illegal operations. Their effect is system dependent": NIL dereference, NIL procedure call, NIL type tests, index out of range, `SET` element outside `0..MAX(SET)`, `SHORT(...)` outside the result type, unterminated strings, and **"8. Overflows"**. The pragma table (from the ETH OP2 compiler) has `V` overflow check and `R` range check (`SHORT`), and says "The ETH compilers have a default of `-` for the R and V pragmas" - **off by default**. |
| `Active-OberonLanguageReport.pdf` | A guard on a number that cannot be represented "raises a trap"; nothing on arithmetic overflow (its one "overflow" is a comment in an example). |
| `Component-Pascal-Report.pdf` §8.2.2 | Real: "If the result of a real operation is too large to be represented as a real number, it is changed to the predeclared value INF with the same sign ... `0.0/0.0` ... has no defined result at all and leads to a run-time error." Integer overflow: **not stated** in the report. |
| Oberon+ specification (`oberon-lang/specification`, §8.2.2, fetched 2026-09-21) | "Oberon+ doesn't require overflow checks. If the representation of the result of an arithmetic operation would require a wider integer type than provided by the type of the expression, the behaviour is undefined; e.g. `MAX(INTEGER)+1` causes an overflow, i.e. the result could be `MIN(INTEGER)` or anything else (even a termination of the program)." Nothing on division by zero or floating point. |

## 3. What the implementations do

Read from source unless marked otherwise.

**voc** (`vishap/compiler/src`, and probed, section 4). `+ - *` are plain C
signed arithmetic; there is no overflow option (its run-time-safety options are
`-p` pointers, `-a` assert, `-r` range, `-t` type, `-x` index). `-r` (off by
default) makes `SHORT` and `CHR` halt with "Value out of range" (Halt(-8)); by
default they truncate. `DIV`/`MOD`: `SYSTEM_DIV`/`SYSTEM_MOD` (runtime/SYSTEM.c)
compute the floored result in C, so a zero divisor is the hardware's `SIGFPE`
- except `if (x == 0) return 0;` first, so **`0 DIV 0` and `0 MOD 0` are 0**.
Reals are C doubles: infinity and NaN, silently.

**OfrontPlus** (`Mod/OfrontOPM.cmdln.cp`): the option `v` is commented "former
ovflchk; neither used nor documented" - Ofront inherited an overflow-check
option from OP2 and it was never implemented. `r` (value ranges) is off, `x`
(indices) on.

**OP2 / Oberon V4 (ETH, Crelier)** (`crelier_r.op2_...pdf`): the thesis
mentions overflow only for compile-time constant expressions. The Linz Oberon
V4 tree here holds binaries and a 4-line `Compiler.Mod` driver, no code
generator: **nothing to read**. The Oakwood `V`/`R` default is the evidence
for ETH compilers (section 2).

**A2 / Active Oberon** (`AOS/oberon/source`): `PCM.OverflowCheck` ("v - perform
overflow check") is declared among the code generator options and **no module
uses it** (`grep OverflowCheck` finds only the declaration; `ArrayCheck`,
`NilCheck`, `PtrInit` etc. are all used). Neither PCG386 nor the Fox
intermediate backend emits an overflow check for `+ - *`. Compile-time errors
204-208 ("product too large", "division by zero", "sum too large", ...) are
the constant folder's. **Not verified locally:** what the x86 runtime does on
a zero divisor (the `Traps` module is not in this tree); the hardware faults.

**Native Oberon 3**: only a disk image is present, no source. Not surveyed.

**Wirth's Oberon-07 (Project Oberon, ARM/RISC)** (`Oberon.ARM.Compiler.pdf`):
`+ - *` and `ABS` compile to plain `ADD`/`SUB`/`RSB` (listing for `ABS` shown),
no overflow trap - the text's "overflow traps" remark is about *compile-time*
folding. `DIV`/`MOD` compile a divisor check: `CMP R0 R10 0 "test for positive
divisor"` then `SWI` (trap). So **a zero or negative divisor traps**, the
strictest reading of the report's "positive divisors". (Project Oberon's own
`ORG.Mod` source is not on this machine.)

**obc (Spivey, Keiko VM)** (`obc-3/runtime`): `PLUS`/`MINUS`/`TIMES`/`UMINUS`
are unchecked C `int` operations. `DIV`/`MOD` are preceded by `ZCHECK`: error
E_DIV, **"DIV or MOD by zero"**; floored quotient. **Real division by zero
traps**: `FZCHECK`/`DZCHECK` raise E_FDIV, "division by zero"; other real
overflow is unchecked (C `float`/`double`). `MIN DIV -1` is C's undefined
division.

**Component Pascal / BlackBox**: the report gives real overflow = `INF`, and
`0.0/0.0` = run-time error (above). **Not verified:** what BlackBox does on
integer overflow (its compiler source is not local; the report is silent).

**ooc / oo2c (van Acken)**: not local (`voc`'s `src/library/ooc` is the
library, not the compiler). Not surveyed.

**The VAX** (`DEC_VAX_Architecture_Handbook.pdf`, 1986), relevant to Phase 14:
the PSW has an **integer overflow trap enable bit (IV, bit 5)**; a `CALLS`/
`CALLG` entry mask sets it from bit 14, so a procedure can choose per
procedure whether integer overflow traps. Division by zero and floating
overflow have no enable flag - they always fault; floating underflow has an
enable bit (FU), cleared on call. VAX floating formats have no infinity or NaN
(a reserved operand faults). So on the VAX backend real overflow *cannot* be a
silent infinity as on IEEE hardware.

## 4. What poc does today (probed 2026-09-21, built `poc`, both size models)

| Case | voc | poc |
|---|---|---|
| `MAX+1`, `MIN-1`, `MAX*2`, `-MIN`, `ABS(MIN)`, `INC(MAX)`, `DEC(MIN)` on `SHORTINT`, `INTEGER`, `LONGINT`, `HUGEINT` | two's-complement wrap at the type's width, all of them, `-O2` and `-OC` | **identical** wrap |
| `7 DIV -2`, `7 MOD -2`, `-7 DIV 2`, `-7 MOD 2` | `-4 -1 -4 1` (floor) | identical |
| `x DIV 0`, `x MOD 0` | `SIGFPE`, exit 136, no message | identical |
| `0 DIV 0` | **0** (SYSTEM_DIV's early return) | `SIGFPE`, exit 136 |
| `MIN(LONGINT) DIV -1` | `SIGFPE` | `SIGFPE` |
| `1.0/0.0`, `0.0/0.0`, `1e300*1e300`, `REAL 1e30*1e30`, `SHORT(1e300)` | `inf`, NaN, `inf`, `inf`, `inf`; no trap | identical |
| `1e-300*1e-300` | 0, silently | identical |
| `REAL 1/0` | `inf` | identical |
| `SHORT(5000000000)`, `CHR(300)` | truncate (705032704, 44); with `-r`: "Value out of range", Halt(-8), exit 248 | truncate, identical to voc's default; no `-r` |
| `INCL(a, 40)` on a 32-bit `SET` | sets bit 8 (a C shift wraps) | identical |

Why poc's integer wrap is a guarantee and voc's is luck: poc's code generator
emits plain `add`/`sub`/`mul`/`sub 0,x` (no `nsw`/`nuw`, `LLVMCodeGenerator.Mod`
lines 1739-1741, 2089, 3565), which LLVM defines as wrapping at any
optimization level; voc's generated C uses signed C arithmetic, undefined by the
C standard, and only wraps because gcc happens to. `sdiv`/`srem` by zero and
`INT_MIN / -1` are LLVM undefined behavior, which x86 turns into `SIGFPE` at
the `-O0` poc's driver uses (it passes no `-O`); C6 already decided that this
is appropriate and needs no message.

## 5. Findings

- **No surveyed dialect traps on integer `+ - *` by default.** voc, obc, A2
  (option present, unused), OfrontPlus (option unused), Wirth's Oberon-07 and
  Oberon+ (explicitly "undefined, no checks required") do not; ETH's OP2
  family defaulted the `V` pragma off. Only Component Pascal/BlackBox is
  unknown.
- **Integer division by zero is the one arithmetic check dialects do make**:
  obc and Wirth's ARM compiler check it explicitly (Wirth's also for a negative
  divisor); voc, and poc, leave it to the hardware signal.
- **Real arithmetic is IEEE and silent in the C-based ones** (voc, OfrontPlus,
  poc); Component Pascal defines `INF` for overflow and a trap for `0.0/0.0`;
  obc traps division by zero. No dialect traps underflow.
- **Range narrowing (`SHORT`, `CHR`)** is unchecked by default and an opt-in
  (`-r`, the `R` pragma) where it exists.

## 6. Decision

**Decided with the user 2026-09-21: items 1-4 below as proposed** (integer
overflow unchecked and documented as wrapping; reals IEEE and silent;
`SHORT`/`CHR`/`SET` element range unchecked, an optional `-r` left to Phase 12
step 1). Recorded in `AGENTS.md` ("Overflow, division and reals"), pinned by
`test/conformance/llvm-overflow-wrap`. The proposal as put to the user:

1. **Integer `+ - * -x ABS INC DEC`: unchecked, wraps at the type's width -
   and say so as poc's behavior**, not "undefined". It is what every dialect
   with a default does, it is what poc emits, and it is testable
   (`llvm-*` fixtures could pin it). Optional later: an opt-in switch
   (`llvm.sadd.with.overflow` and a trap with a message, like the other seven
   traps) - to be triaged with Phase 12 step 1's safety checks, and to be
   revisited for the VAX backend, whose `IV` bit makes it nearly free there.
2. **Integer `DIV`/`MOD`**: floored for every non-zero divisor (as now, same as
   voc); a zero divisor and `MIN DIV -1` end by `SIGFPE` (C6, already
   decided). poc's `0 DIV 0` differs from voc's `0` (a quirk of `SYSTEM_DIV`;
   keep poc's).
3. **Reals**: IEEE, silent - overflow gives infinity, invalid gives NaN,
   underflow gives 0 or a denormal, division by zero gives infinity. As voc.
   (On the VAX backend this cannot hold; Phase 14 decides what a real
   overflow does there.)
4. **`SHORT`/`CHR` out of range and `SET` elements out of range**: leave as
   they are (unchecked); list an optional `-r` in the Phase 12 step 1 triage.
5. Then write C9's table from section 4 above, and record 1-4 in `AGENTS.md`.

### Note: `ENTIER` (2026-09-21)

`ENTIER` of a value outside `LONGINT` traps (A4, exit status 8) although the
decision above leaves every other arithmetic operation silent. Reconsidered
right after this survey and **kept, on purpose** (user): a wrapped sum is the
correct result modulo 2^n and programs use it deliberately, while no value is
right for `ENTIER(1E30)` - the report defines it only for a value that fits, and
voc's answer differs between `-O2` and `-OC` - so the trap loses nothing
legitimate; and relaxing it to saturation later could never break a working
program, where tightening a silent value could. C9's table lists it as the one
arithmetic conversion that traps.
