# ASSERT: what other Oberons do (Phase 11, A14)

Written 2026-09-25 for inventory item A14 (`ASSERT`: add it or not, which form,
what `-a` means) - the one question left in `PLAN.md`'s "Open design
questions". `Oberon2.pdf` has no `ASSERT`: its §10.3 table of predeclared
procedures lists 20 names, none of them `ASSERT`. This file says what each
source does, what was probed and what was only read, and ends with the decision
(user, 2026-09-25) and what poc now does.

## 1. The questions

1. Should poc have `ASSERT` at all, as an extension beyond `Oberon2.pdf`?
2. Which forms: `ASSERT(x)`, `ASSERT(x, n)`, both; what may `n` be?
3. What happens when `x` is FALSE: message, exit status?
4. A condition that is a constant FALSE: compile-time error or run-time trap?
5. Can assertions be switched off, and if so, is the condition still evaluated?

## 2. What the language definitions say

| Source (local file) | Says |
|---|---|
| `Oberon2.pdf` | No `ASSERT`. |
| `Oberon2-Report.pdf` (1993) | §10.3's table has `ASSERT(x)` and `ASSERT(x, n)` (`n` an integer constant), "terminate program execution if not x", and `HALT(n)`: "In ASSERT(x, n) and HALT(n), the interpretation of n is left to the underlying system implementation." Not in §4's list of predeclared identifiers. `Oberon2.pdf` dropped both rows. |
| `oop_in_oberon-2_book.pdf` (Mössenböck, 2nd ed., Appendix A) | Both forms, "terminate with error n if not x", and `ASSERT` in the §A.4 predeclared list too. |
| `Oberon-2012/Oberon07.Report.pdf` (Wirth, 2016) | `ASSERT(b)`, BOOLEAN: "abort, if ~b". One argument only. |
| `Oberon-2-2020/The-Revised-Oberon2-Programming-Language.pdf` (Pirklbauer, 2023) | Describes only its additions to Oberon-07, so it inherits `ASSERT(b)`. |
| `Active-OberonLanguageReport.pdf` | `ASSERT(x)`: "raise trap, if x not true". |
| `Component-Pascal-Report.pdf` §10.3 | `ASSERT(x)`, and `ASSERT(x, n)` with `n` an **integer constant**: "terminate program execution if not x". "In ASSERT(x, n) and HALT(n), the interpretation of n is left to the underlying system implementation." |
| Oberon+ specification (`OberonPlus/specification`) | The Component Pascal text, word for word. |
| oo2c's copy of the Oberon-2 report (`oo2c/doc/language/oberon2.texi`) | The same two rows and sentence, added to the Oberon-2 table. |
| `oakwood-guidelines.pdf` | Does not define `ASSERT`, but its pragma table (from ETH's OP2) has `A`, "ASSERT generation", default `+` - it assumes the compiler has one. |

## 3. What the implementations do

Probed means compiled and run here; read means taken from the source.

| Implementation | Forms, `n` | On failure | Constant FALSE | Switch |
|---|---|---|---|---|
| **voc** 2.1.0 (probed, both size models; `OPB.Mod`, `Modules.Mod`) | `(x)`, `(x, n)`; `n` an integer constant in 0..255 (err 69 otherwise not constant, err 218 out of range) | stderr "Assertion failure." and, for `n # 0`, " ASSERT code n."; exit `n` if `n > 0`, else 255. Buffered `Out` output written before it is lost (no flush) | compile-time error, err 99 "ASSERT fault" (`ASSERT(FALSE)`, `ASSERT(SIZE(R) = 3)`) | `-a`, on by default. Off: **the condition is not evaluated** (a side effect in it does not happen) |
| Ofront, OfrontPlus (read, `OfrontOPB`) | as voc (the same OP2 code) | default trap 0 (OfrontPlus: -1) | err 99, as voc; OfrontPlus accepts it in its Oberon-07 mode (`OPM.Lang = "7"`) | not checked |
| BlackBox / Component Pascal (read, `Dev/Mod/CPB.odc`, docs) | as voc | default trap 0 | **allowed**: `ASSERT(FALSE, n)` becomes an unconditional trap (the OP2 code without voc's err 99) | its guidelines say checks "cannot be switched off in a production system" |
| A2 / AOS (read, `FoxSemanticChecker.Mod`, `FoxIntermediateBackend.Mod`) | `(x)`, `(x, n)`; `n` an integer constant, any value | trap 8 by default, else trap `n` | compile-time error "assert failed", except in unreachable code (the source records an argument about Oberon-07 code using `ASSERT(FALSE)` in place of `HALT`) | backend option `noAsserts`; off: condition not evaluated |
| obc 3 (probed) | `(x)`, `(x, n)`; `n` **any integer expression** | "Runtime error: assertion failed (n) on line L in module M" and a traceback; exit 2 whatever `n` | allowed, fails at run time | none |
| oo2c (read, `RT0.c`) | `(x)`, `(x, n)`; `n` an integer constant | "Runtime error in module M at pos P / Assertion failed, code n" and a backtrace; one fixed exit status | not checked (read) | - |
| OBNC (read, `OBNC.h`) | `(b)` (Oberon-07) | "Assertion failed at line L in file F"; `abort()` | - | - |
| Project Oberon (read, `PO.Applications.pdf` listings) | `(b)` | a trap (the generated code branches to the trap routine) | not verified: no compiler source here | - |
| Native Oberon 3 | not checked: only disk images here, no source | | | |

BlackBox also has a convention for `n` (Tut-3, BB-Rules): 0..19 free (19 for a
temporary breakpoint), 20..59 preconditions, 60..99 postconditions, 100..120
invariants.

## 4. Findings

- Every surveyed dialect but strict Oberon-2 has `ASSERT`; every Oberon-2 and
  Component Pascal descendant has both `ASSERT(x)` and `ASSERT(x, n)` with a
  constant `n`. obc's run-time `n` is the only exception.
- voc's own libraries (`src/library`) use `ASSERT` 217 times in 38 files, 35 of
  them with a code and none with a constant FALSE. Phase 12, which brings voc's
  module inventory to poc, needs it whatever is decided here.
- Nobody has a message-string form (`ASSERT(x, "text")`), which `PLAN.md` had
  floated.
- Where assertions can be turned off (voc, A2), the condition is then not
  evaluated at all.
- A constant FALSE condition splits them: voc, Ofront, OfrontPlus (outside its
  Oberon-07 mode) and A2 (outside unreachable code) reject it; BlackBox, obc and
  OfrontPlus's Oberon-07 mode accept it as an unconditional trap - the Oberon-07
  idiom for "cannot happen", where Oberon-07 has no `HALT`. Oberon-2 has `HALT`.
- An exit status of `n` (voc) makes `ASSERT(x, 0)` look like success; voc maps
  it to 255. The others use one status or a trap number of their own.

## 5. Decision (user, 2026-09-25) and what poc does

As recommended:

1. **Adopted as an extension beyond `Oberon2.pdf`**, a predeclared procedure
   like `HALT` (`PredeclaredProcedures.CheckAssert`, `LLVMCodeGenerator.
   GenerateAssert`). A module may still declare its own `ASSERT`, which hides
   it. `-strict` (Phase 11 step 6) must reject it; poc's own source does not
   use it.
2. **`ASSERT(x)` and `ASSERT(x, n)`**: `x` a BOOLEAN expression, `n` an integer
   constant in 0..255, as `HALT`'s argument - voc's rule.
3. **A failure traps like poc's other traps**: "assertion failed", or
   "assertion failed (n)", and a newline on stderr, exit status **10** whatever
   `n` is (poc's own numbering, as for statuses 2..9). The condition is always
   evaluated. poc's `Out` is not buffered, so nothing written before is lost.
4. **A constant FALSE condition is a compile-time error**, "ASSERT condition is
   always FALSE", as in voc, Ofront and A2 (BlackBox and obc accept it) and as
   C9 decided for every trap the compiler
   can see coming. So `ASSERT(SIZE(T) = 8)` is a compile-time check. `HALT`
   marks code that must not be reached.
5. **Always on, no switch.** voc's `-a` belongs to Phase 12 step 1's triage of
   voc's switches; if one is added, the condition is then not evaluated, as in
   voc and A2, and that is documented.
6. **No message-string form.** The file-and-line switch (C7) would say more, and
   for every trap.

Fixtures: `llvm-assert` (each case under both size models; the same assertion
fires as under voc) and `semantic-reject-assert` (the same ten lines voc
rejects, and four accepted ones).
