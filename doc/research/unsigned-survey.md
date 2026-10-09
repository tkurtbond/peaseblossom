# Unsigned integer types: what other languages do (Phase 19, candidate 5)

Written 2026-10-08 for Phase 19's candidate 5 in `PLAN.md`: unsigned
integer types, `SYSTEM.UINT8`, `UINT16`, `UINT32` and `UINT64`, whose
arithmetic wraps on overflow and underflow (the user, 2026-10-08: the
maximum plus one is 0, and 0 minus one the maximum). The need was found by
the user's FLTK binding (`~/Repos/Oberon/pofltk`), which declares C's
unsigned types as the signed `SYSTEM.INTn` of the same width. Those pass
the bits but compare, divide and widen as signed. `Fl.RGB` builds an
`Fl_Color`, a C `unsigned int`, as
`SYSTEM.VAL(INTEGER, LONG((r * 256 + g) * 256 + b) * 256)`, and a color
whose red is 128 or more is then a negative `INTEGER` under `-OC`.

The questions: where such types sit among the integer types, what mixing
them with signed ones does, how a value is converted between the two
families, what the operations mean, and what their constants are. Nothing
here changes poc.

The reports are local files under `~/Reference/Computer/Languages/`, and
the compilers' sources are under `/usr/local/sw/src/lang/Oberon/`, all read
on the date above. XDS's documentation is not local. It was read from the
sources of its manual in `github.com/excelsior-oss/xds`
(`Sources/Doc/Comp/src/oberon2.tex`, last changed 2019-06-10 in commit
`88cd0674`), also on that date.

## 1. poc today

- `SYSTEM.INT8`, `INT16`, `INT32` and `INT64` are signed integers of exactly
  that width under both size models, placed among `SHORTINT ⊆ INTEGER ⊆
  LONGINT ⊆ HUGEINT` by size (Reference Guide, sections 1 and 4).
- Integer `+ - *`, unary `-`, `ABS`, `INC` and `DEC` wrap at the type's width
  (`language-extensions.md`, "Overflow, division and reals"). `DIV` and
  `MOD` floor.
- Constants fold in 64-bit signed arithmetic. A hexadecimal constant may be a
  64-bit pattern (`language-extensions.md`, "Hexadecimal constants as
  64-bit patterns"), so `0FFFFFFFFFFFFFFFFH` is -1.
- `SYSTEM.VAL` reinterprets bits, and `LONG`/`SHORT` convert by size.
- voc has no unsigned types. Its `OPC.Mod` only reserves `UINT8` to `UINT64`
  as names in the C it writes ("pseudo keyword used by voc"), so no
  Oberon identifier collides with its C macros.

## 2. The Oberon family

**The reports.** Only Oberon-07 and the reports that follow it have an
unsigned type, and only one byte wide. Active Oberon has the full set.

| Source | Unsigned integers |
|---|---|
| `Oberon.Report.pdf` (1990), `Oberon2.pdf` | None. "Numbers are (unsigned) integers" means only that a literal has no sign. |
| `Oberon-2012/Oberon07.Report.pdf` (revision 1.10.2013 / 3.5.2016) §6.1 | `BYTE`, "the integers between 0 and 255". "The type BYTE is compatible with the type INTEGER, and vice-versa." Oberon-07 has one other integer type, `INTEGER`. Its `SYSTEM` for the RISC processor has `UML(m, n)`, "unsigned multiplication", on `INTEGER`s. |
| `Oberon-2-2020/The-Revised-Oberon2-Programming-Language.pdf` (Pirklbauer, 1.5.2023) | Describes only its changes to Oberon-07, and keeps Oberon-07's `BYTE`. |
| `Component-Pascal-Report.pdf` | `BYTE` is signed, -128..127. No unsigned type. |
| `Active-OberonLanguageReport.pdf` ("ETH Oberon (2019) Language Report", Friedrich and Negele, October 31, 2019) §7.1 | `UNSIGNED8` to `UNSIGNED64` beside `SIGNED8` to `SIGNED64`, and `ADDRESS`, "unsigned integers in address range". See below. |
| `oakwood-guidelines.pdf` (October 20, 1995) §3.2 | "Enumerations and unsigned types have been specifically rejected by ETH although they are still found desirable by applications programmers. Unsigned types are particularly important when interfacing to existing external standard libraries such as X Windows, 'C' or Windows." See below. |
| Oberon+ (`OberonPlus/specification`, last commit 2026-03-02) | `BYTE`, 0..255, beside signed `INT8` to `INT64`. Its inclusion relations are `INT64 >= INT32 >= INT16 >= INT8` and `INT16 >= BYTE`: `BYTE` is included in the smallest signed type that holds all its values, not in `INT8`. |

**The Oakwood Guidelines** (§3.2.1, "Type inclusion Hierarchies") give the
one general rule for adding such types to Oberon-2. "Separate type
inclusion hierarchies should be used to separate families of types which
are intrinsically incompatible. Explicit conversion procedures should be
used to convert values that can be represented in different type inclusion
hierarchies. The predefined function procedures LONG and SHORT should
provide conversion within any extended type hierarchy." Their example,
"NOT a proposal for general implementation", is `LONGCARD ⇒ CARDINAL ⇒
SHORTCARD` beside `LONGCOMPLEX ⇒ REAL ⇒ LONGINT ⇒ INTEGER ⇒ SHORTINT`. They
add that "such procedures should be included as built in procedures".

**Active Oberon**, as the report describes it and as the Fox compiler
(`AOS/oberon/source`, a copy from December 2023) implements it:

- One chain, not two. §14.3 gives `UNSIGNED64 ⊐ SIGNED64 ⊃ UNSIGNED32 ⊐
  SIGNED32 ⊃ UNSIGNED16 ⊐ SIGNED16 ⊃ UNSIGNED8 ⊐ SIGNED8`, where `A ⊐ B`
  means only that a `B` may be assigned to an `A`, "while there is not
  really a superset relationship".
- So a signed value may be assigned to an unsigned type of the same size or
  wider, and its sign is lost. "Unsigned integers are compatible with signed
  or unsigned integer of same or smaller size. This implies that the
  assignment from a signed to an unsigned integer of same size is considered
  ok. The other direction does not work." The report's examples
  (§7.1.2) are `u16 := s8; (∗ ok ∗)`, `u16 := s16; (∗ ok ∗)`,
  `s16 := u8; (∗ ok ∗)`, `s16 := u16; (∗ error ∗)` and
  `s16 := SIGNED16(u16); (∗ ok ∗)`.
- In Fox, `FoxGlobal.BasicTypeDistance` makes an integer type compatible
  with another of the same size or larger whenever the target is unsigned,
  or is signed and larger. The same-size unsigned-to-signed case gets
  `MIN(SIZE)`, which stays negative and so becomes incompatible.
  `ConvertOperands` (`FoxSemanticChecker`) converts a binary expression's
  operands to whichever of the two types the other is compatible with, so
  `SIGNED16 + UNSIGNED16` is computed as `UNSIGNED16`.
- A type's name converts explicitly, `SIGNED16(u16)`. An unsigned type may
  not be converted from a float ("invalid unsigned type in explicit
  conversion").
- `SHORT` and `LONG` stay within the unsigned family (`UNSIGNED16` to
  `UNSIGNED8`, and so on).
- Constants fold as signed 64-bit values. `DIV` and `MOD` of unsigned
  operands fold as `UNSIGNED64`, and a non-negative constant that fits may
  be assigned to an unsigned type.
- The reason given (§7.1.3): "We introduced unsigned integer types because
  they can come handy and because they behave different for fundamental
  operations such as shifts or comparisons." §13 advises using "an unsigned
  type when it is important that the sign bit is not propagated for
  right-shifts".

**The other compilers.** None of these has an unsigned type that a program
can name: voc, Ofront, OfrontPlus, oo2c, obc, OBNC, BlackBox (`bbcp`),
Linz Oberon V4, Native Oberon 3 and Oberon+ (beyond its `BYTE`). Each
project's Oberon and Component Pascal sources were searched for
`UNSIGNEDn`, `UINTn`, `CARDINAL`, `CARDn`, `SHORTCARD` and `LONGCARD`. The
only hits are beside the point:

- OfrontPlus's `Mod/Lib/MathLib.cp`, a Modula-2 library carried over, uses
  `CARDINAL`.
- Oberon System 3's `BIT` module (1996, in Oberon+'s demos) declares
  `SHORTCARD* = SHORTINT`, `CARDINAL* = INTEGER` and `LONGCARD* = LONGINT`.
  It gives them the unsigned operations as procedures: `SLESS`, `ILESS` and
  `LLESS`, `SLESSEQ` to `LLESSEQ`, and `SDIV` to `LDIV`. That is Modula-3's
  answer (section 5), in Oberon.

## 3. XDS

XDS's Oberon-2 (manual, "Whole system types") has `SYSTEM.CARD8`, `CARD16`
and `CARD32`, unsigned and exactly that wide, beside `SYSTEM.INT8`, `INT16`
and `INT32`. "These types were introduced to simplify constructing the
interfaces to foreign libraries", the same need as pofltk's. There is no
64-bit cardinal. The two families are separate hierarchies, both under the
reals:

- `SYSTEM.CARD32 ⊇ SYSTEM.CARD16 ⊇ SYSTEM.CARD8`;
- `LONGREAL ⊇ REAL ⊇` {signed types, unsigned types}.

So no unsigned type is included in a signed one, nor the other way, as the
Oakwood Guidelines recommend. `SYSTEM.CARD8`, like `CHAR`, `BOOLEAN` and
`SHORTINT`, may be assigned to a `SYSTEM.BYTE`. Under XDS's Modula-2,
whose `CARDINAL` is 16 or 32 bits by an option, an Oberon module is told
to use `SYSTEM.CARD` for an imported `CARDINAL`.

## 4. Modula-2

| Source | Unsigned integers |
|---|---|
| PIM4's report (`Modula-2-Report-from-PIM2-4E-1988_...pdf`) | `CARDINAL`, "the integers between 0 and MAX(CARDINAL)". A literal 0..MaxInt "can be considered as either of type INTEGER or CARDINAL". Above MaxInt it is a `CARDINAL`. `+ - * DIV MOD` take two `CARDINAL`s or two `INTEGER`s, never one of each. "Sign inversion applies to operands of type INTEGER or REAL", not to `CARDINAL`. Assignment, though, is allowed in both directions: "assignment compatible, if either they are compatible or both are INTEGER or CARDINAL". A search for "overflow" finds nothing. |
| ISO 10514-1, through Schönhacker and Pronk's paper (`ISO-IEC-10514-1-...-additions.pdf`) | `CARDINAL` stays. `LONGCARD` was deliberately left out, in favor of subranges. The paper sets the checked conversion, `c := VAL(CARDINAL, i); (* safe *)`, against the reinterpretation, `c := CAST(CARDINAL, i); (* unsafe *)`. Range overflow is a language exception (`M2EXCEPTION`). |
| GNU Modula-2 (`gm2-15.pdf`, GCC 15) | `SHORTCARD`, `CARDINAL` and `LONGCARD` as C's unsigned types, and in `SYSTEM` `CARDINAL8`, `CARDINAL16`, `CARDINAL32` and `CARDINAL64` beside `INTEGER8` to `INTEGER64` ("for most architectures"). "Two sub expressions of INTEGER and CARDINAL are not expression compatible", and gm2 extends that "across all fixed sized data types (imported from SYSTEM)". Assignment is allowed within a family of different sizes. Overflow is checked only with `-fwholevalue` ("detect whole number overflow and underflow"). |

## 5. Modula-3

`Modula-3_Language_Definition.pdf` (SIGPLAN Notices, August 1992) has no
unsigned type. `CARDINAL` is the subrange `[0..LAST(INTEGER)]`, a
non-negative `INTEGER`, not an unsigned one. The unsigned operations are
procedures of the interface `Word` on `Word.T = INTEGER`:

- `Plus`, `Minus` and `Times`, each "MOD 2^Size";
- `Divide` and `Mod`;
- `LT`, `LE`, `GT` and `GE`, "unsigned x < y" and so on;
- `And`, `Or`, `Xor`, `Not`, `Shift` ("with 0 fill"), `Rotate`, `Extract`
  and `Insert`.

The type stays signed, and a program asks for the unsigned meaning
operation by operation.

## 6. What this means for poc

Four answers to where the types sit:

1. **No types, procedures** (Modula-3's `Word`, Oberon System 3's `BIT`).
   The least change to the language, and the most to every program: each
   comparison, division and right shift is a call. It does not fix
   pofltk's `Fl_Color`, whose comparison and division stay signed unless
   written as calls.
2. **A separate family** (Oakwood's recommendation, XDS, gm2's expression
   rule). `UINT8 ⊆ UINT16 ⊆ UINT32 ⊆ UINT64`, apart from `SHORTINT ⊆ … ⊆
   HUGEINT`, both under `REAL ⊆ LONGREAL`. An expression mixing the families
   is an error, and conversion between them is explicit.
3. **A separate family, included where no value is lost** (Oberon+'s
   `INT16 >= BYTE`, extended). As 2, but `UINTn` is also included in every
   signed type wider than n bits, so `UINT8 + INTEGER` is an `INTEGER`. A
   signed value never becomes unsigned without a conversion, and `UINT64`
   mixes with no signed type.
4. **One chain** (Active Oberon). `UINTn` sits just above `INTn`, so a signed
   value goes into an unsigned type of its size without a word, and its sign
   is lost. That is the conversion the FLTK binding writes out with
   `SYSTEM.VAL` today, made implicit.

Precedent and poc's own rules both point to 2 or 3. Under 4, `u := i` with
a negative `i` silently gives a large value, which is the C behavior the
others avoid. 3 differs from 2 only in convenience, and inherits the
oddity that `SYSTEM.INTn` already has: whether `UINT16 + INTEGER` compiles
depends on the size model, since `INTEGER` is 16 bits under `-O2` and 32
under `-OC`.

The other open questions, with what each source does:

- **Conversions between the families.**
  - Active Oberon uses the type's name, `SIGNED16(u)`; ISO Modula-2 uses
    `VAL` (checked) and `CAST` (unchecked); Oakwood asks for built-in
    procedures.
  - poc already has the unchecked one, `SYSTEM.VAL`, for same-width
    reinterpretation, and `LONG`/`SHORT` by size. Within the unsigned family
    `LONG` and `SHORT` serve as Oakwood and Fox have them.
  - A value-checked conversion would be new. `-range-checks` already makes
    `SHORT` trap on a value that does not fit, and could do the same for a
    conversion between the families.
- **Operations.**
  - Comparison, `DIV`, `MOD` and right shifts are where unsigned differs
    (Active Oberon §7.1.3 and §13, Modula-3's `Word`, Oberon System 3's
    `BIT`).
  - `DIV` and `MOD` of non-negative values floor and truncate alike, so
    poc's choice of floor does not arise.
  - Unary minus is refused by PIM4 for `CARDINAL`. With wrapping both ways,
    as the user wants, it would be 0 - x.
  - `ABS` is the identity.
- **Constants.** Fox folds as signed 64-bit values, with unsigned `DIV` and
  `MOD`. poc folds in 64-bit signed arithmetic too, so `UINT64` constants
  above `MAX(HUGEINT)` need either unsigned folding or the hexadecimal
  pattern extension, which already gives such a constant its bits.
- **Overflow.** Only gm2 and ISO Modula-2 check it, by an option or an
  exception. Modula-3's `Word` and Active Oberon wrap. Wrapping, as the user
  asks, is poc's rule for the signed types already.
- **The widest type.** XDS stops at 32 bits. Active Oberon and gm2 have 64.
  pofltk needs 8 and 32 (`unsigned char`, `Fl_Color`), and `size_t` is 64
  bits on 64-bit targets.

**Decided** with the user 2026-10-08: option 2, as `SYSTEM.CARD8` to
`CARD64`, included in the reals, with `SYSTEM.VAL` the only conversion
between the families and unary minus allowed.
`doc/developer/language-extensions.md`, "Unsigned integer types", has the
extension.
