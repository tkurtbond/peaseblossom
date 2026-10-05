# Assigning strings and character arrays: what other Oberons do (Phase 11, A21)

Written 2026-09-21 for inventory item A21 ("relax assignment-compatibility
rule 6; assign an `ARRAY OF CHAR` to another; other array types"), the survey
`000-todo.org` asked for before any decision. It says what each source *does*,
marks what could not be verified, and ends with what poc does today (probed)
and a proposal. Nothing here changes poc.

## 1. The questions

1. A string constant that exactly fills the destination (`m = n`, no room for
   the terminating `0X`) or is longer (`m > n`): accepted, truncated, trapped,
   or a compile-time error?
2. One character array assigned to another: fixed to fixed (same type,
   different types, different lengths), open to fixed, fixed to open, open to
   open.
3. What a too-short destination does when the length is only known at run time:
   truncate, trap, or (voc's way) something else.
4. Whether any of it extends past `ARRAY OF CHAR`.

Rule 6 of `Oberon2.pdf` (Appendix A, "Assignment compatible"): *"Tv is ARRAY n OF
CHAR, e is a string constant with m characters, and m < n"* - `m` counts the
characters without the `0X`, so a string is accepted only if it leaves room for
the terminator. Rule 1 is "Te and Tv are the same type", and "same type" (App.
A) covers two variables *"in the same identifier list ... and are not open
arrays"* - an open array is never the same type as another open array.

## 2. What the language definitions say

| Source (local file) | Says |
|---|---|
| Oberon 1990, §9.1 (`Oberon.Report.pdf`) | "Strings can be assigned to any variable whose type is an array of characters, provided the length of the string is less than that of the array"; the result is `a[i] = s[i]`, `a[n] = 0X`. Nothing on assigning one array to another beyond "same type". |
| Oberon-2, both PDFs | Rule 6 (`m < n`) and rule 1 (same type), as above. |
| Oberon-07 (2016, `Oberon07.Report.pdf`) §9.1 | "The type of the expression must be the same as that of the designator", with exceptions: (2) a string to any array of characters if shorter than the array, "(A null character is appended)", and a one-character string to a `CHAR`; **(4) "An open array may be assigned to an array of equal base type."** No length rule is stated for (4). |
| Active Oberon (`Active-OberonLanguageReport.pdf`) | (1) "equal types and no open arrays"; (6) `ARRAY n OF CHAR` and a string constant, `m < n`; **(7) "Tl is ARRAY OF CHAR and r is a string constant"** (an open target). |
| Component Pascal (`Component-Pascal-Report.pdf`) §9.1 (3), App. A rule 6 | Any `String` (a string constant *or a character array holding a 0X-terminated string*) may be assigned to an `ARRAY OF CHAR` if `LEN(e) < LEN(v)`: "`v[i]` becomes `e[i]` for `i = 0..m-1` and `v[m]` becomes 0X. **It leads to a run-time error if m >= LEN(v).**" Equal types are assignable only if not "open array types". |
| Oberon+ (`oberon-lang/specification` §9.2, fetched 2026-09-21) | (3) `ARRAY n OF CHAR` and a string of length `m < n`, as rule 6; **(4) "if Tv and Te are open or non-open CHAR arrays, `v[i]` becomes `e[i]` for `i = 0..STRLEN(e)`; if `LEN(v) <= STRLEN(e)` or `e` is not terminated by 0X the program halts"**; **(5) "if Tv is an open CHAR array and e is a string ... if `LEN(v) <= LEN(e)` the program halts"**. Array-to-array in general needs equal types. `COPY` is "deprecated" and truncates. |
| Oakwood guidelines §2.3, §2.5 | Unterminated strings are an "illegal operation, system dependent"; a character array used as the source of `COPY` "must contain 0X as a terminator". Nothing on assignment. |

## 3. What the implementations do

**voc** (`vishap/compiler/src/compiler/OPB.Mod`, `CheckAssign`, and probed in
section 4). Array targets: `x = y` (same type; voc treats structurally equal
anonymous array types as the same - observed: `s1`, `s2` declared separately
are assignable); or *"`y.comp = Array`, same base type, `y.n <= x.n` (OK by
Oberon-07/2013)"* - any element type, a **shorter or equal fixed array into a
longer one**; or *"`y.comp = DynArr`, same base type (OK by Oberon-07/2013,
length tested at runtime)"*; or `x` an array of `CHAR` and `y` a string constant
(error 114 "string too long to be assigned" if its length including `0X` exceeds
`x.n`, so `m < n`, as rule 6). **An open array is never a target** (error 113).
Generated code: `memcpy` of the *source's* size, whole array, terminator
ignored (`__MOVE(src, dst, size)`); for an open source
`__MOVE(s, r.a, __X(s__len * 1, n+1))`, which traps "Index out of range"
(Halt(-2)) if `LEN(source) > LEN(destination)` **whatever the source holds**: a
terminated `"ab"` in an 8-character buffer cannot be assigned to a 4-character
array. The tail of a longer destination is left as it was.

**OfrontPlus** (`Mod/OfrontOPB.cp`): same lineage; string constants as voc
(err 114). In its Oberon-07 mode (`OPM.Lang = "7"`) a fixed array of the same
length and base, and an open `CHAR` array into a fixed `CHAR` array (`StrDeref`),
are assignable; otherwise strict Oberon-2.

**A2 / Active Oberon** (`AOS/oberon/source/FoxSemanticChecker.Mod`,
`CompatibleTo`; `I386.Builtins.Mod`): equal types are assignable *only if not
open*; a string constant to a character array is assignable if the target is
**open** or `staticLength >= string length` (length counts the `0X`, so
`m < n`); a fixed array of another type only if `SameType`. There is no
open-to-fixed or fixed-to-fixed-of-different-length assignment. String
assignment compiles to `CopyString`, which **truncates**: it moves
`min(LEN(dest), LEN(src))` bytes and forces `dest[l1-1] := 0X` (the source says
"old PACO semantics"), so a too-long string into an open target is silently cut.

**obc** (`obc-3/compiler/expr.ml`, `check_assign1`; read, not run - no `obc` is
installed): a string constant is assignable to a string-typed target when
`bound lt >= bound rt` (`m < n`); otherwise `subtype` (same types); with the
`-ob07` flag also "`is_array lt && is_flex rt` with the same base type" (Oberon-07
rule 4). Default: strict Oberon-2.

**Component Pascal / BlackBox**: the report only (above); the compiler is not
local. **Not surveyed** (no source here): Native Oberon 3 (disk image only),
Linz Oberon V4 (binaries), ooc/oo2c, Project Oberon's `ORG.Mod`/`ORP.Mod`.

## 4. What poc does today (probed 2026-09-21, built `poc`, both compilers)

`R = RECORD a: ARRAY 4 OF CHAR; canary: ARRAY 4 OF CHAR END`; `Nm`, `Big` are
named 4- and 8-character arrays.

| Assignment | voc | poc |
|---|---|---|
| `r.a := "abc"` (`m < n`) | ok | ok |
| `r.a := "abcd"` (`m = n`), `"abcdefg"` (`m > n`) | error 114 | "assignment is not type-compatible" (same) |
| `y := x`, both `Nm` | ok | ok |
| `s1 := s2`, separately declared `ARRAY 4 OF CHAR`s | **ok** (structural) | error: not the same type (as the report) |
| fixed 4 to fixed 8 (`b1 := x`) | ok, copies 4, tail of `b1` kept (`xy~~efg~`) | error |
| fixed 8 to fixed 4 | error 113 | error |
| same type `Big`, terminator in the middle | whole array copied (`ab~defg~`) | identical |
| `INTEGER` arrays, same type / 4 into 6 / open into 4 | ok / **ok** / **ok** | ok / error / error |
| open `ARRAY OF CHAR` (value or `VAR`) into a fixed 4-character array | ok if `LEN(src) <= 4`; **trap "Index out of range" if `LEN(src) > 4`, even when the string it holds is short** (exit 254) | error |
| fixed into open `VAR d`, string constant into open `VAR d` | error 113 (both) | error (both) |
| **open into open** (`VAR d, s: ARRAY OF CHAR; d := s`) | error 113 | **accepted by `-check`; the backend then emits invalid IR and `clang` fails** ("expected number in address space ... `load <unsupported>`") |

The last row is a **defect in poc**, independent of the decision below. `d, s`
in one parameter list share one `Types.ArrayType`, and
`Types.AssignmentCompatible`'s rule 1 is `SameType(dst, src)`, which is true for
an object and itself; the report's "same type" excludes open arrays (and so do
Active Oberon's "no open arrays" and Component Pascal's "nor open array types").
It is the same shape as A10's finding (the checker accepts what the backend
cannot lower). Separately, `COPY(x, v)` (probed, identical in voc and poc)
already truncates: it copies up to the source's terminator, at most `LEN(v)-1`
characters, and always terminates (`COPY(b, r.a)` with `b = "abcdefg"` gives
`abc`, the neighbouring field untouched).

## 5. Findings

- **Rule 6 is the same everywhere.** No surveyed dialect accepts an exact fit or
  a longer string constant: voc error 114, A2 `m < n` (length counts the `0X`),
  obc `bound lt >= bound rt`, Component Pascal `LEN(e) < LEN(v)`, Oberon+ `m < n`.
  The relaxations the todo item names - exact fit, or a longer string truncated -
  exist nowhere at compile time. (The only truncating assignment is A2's
  run-time `CopyString` into an *open* target.)
- **One character array into another** is where dialects differ, and there are
  three designs: (a) **none - only the same type** (Oberon-2, A2, obc default,
  Active Oberon); (b) **by terminator, halting if it does not fit** (Component
  Pascal, Oberon+): copy `e[0..m-1]` and a `0X`, trap if `e` is not terminated or
  `m >= LEN(v)`; (c) **by size, whole array** (voc, Oberon-07 rule 4, OfrontPlus's
  Oberon-07 mode): copy `LEN(e)` elements, trap (voc) if `LEN(e) > LEN(v)`.
- **(b) accepts every case where (c) gives a valid result and more**: a
  terminated string shorter than its buffer. The visible string is the same;
  only bytes after the terminator differ. voc's trap by *length*, not by
  contents, is the less useful rule.
- **An open array as the *target*** is accepted only by Active Oberon (string
  constant, rule 7), Oberon+ (rules 4, 5) and Component Pascal (`ARRAY OF CHAR`
  target with a string) - never by voc, and never by A2 for an array source.
- **Beyond `CHAR`**: only voc (any element type, fixed shorter-or-equal, or an
  open source) and Oberon-07 rule 4 (open array to an array of equal base type)
  go there. Those copy whole arrays by size and leave the destination's tail
  alone. No surveyed use is named.
- **poc**: rule 6 exactly; same-type array assignment as the report says;
  and one defect (open into open).

## 6. Proposal and decision

**Decided with the user, 2026-09-21** (options as numbered below): 1 kept; 2
done; 3 *voc's rule* (whole array by size, `LEN(e) <= LEN(v)`, any element
type, `CHAR` included) rather than the recommended terminator-based rule; 4
*yes, as voc does* - which is the same rule, so item 3 already covers other
array types. The rule is voc's, so it accepts what voc accepts and traps where
voc does (a longer open source; exit status 9 in poc, "open array assigned to
an array too short for it"), and `llvm-array-assign` compares it with voc under
both size models. `AGENTS.md`, "Array assignment", is the user-facing account.
Recorded against the recommendation: the terminator-based rule accepts every
terminated string voc's rule does and more, and can be added later without
breaking a program written under this one.

The proposal as it was made:

1. **Rule 6 stays as it is** (a compile-time error for `m >= n`): every dialect
   agrees, and truncation is what `COPY` is for.
2. **Fix the defect regardless**: `SameType`'s use as assignment rule 1 must
   exclude open arrays, so `d := s` between open arrays is a front-end error, as
   it is in voc (113) and by the definitions of the report, Active Oberon and
   Component Pascal. No test-visible change for a valid program.
3. **Extend, or not, character-array assignment** - the choice is between:
   - *Nothing*: the report's rules plus item 2; `COPY` remains the tool.
   - **Terminator-based, halting (Component Pascal / Oberon+) - recommended if
     extending**: `v := e` where `v` and `e` are any `ARRAY OF CHAR` (fixed or
     open) copies `e` up to its first `0X` and appends a `0X`; the program stops
     with a message ("string too long for the array it is assigned to", exit
     status 9) if `e` has no `0X` or `m >= LEN(v)`. Also a string constant into
     an *open* `ARRAY OF CHAR` (A2 rule 7, Oberon+ 5), halting if it does not fit.
     It accepts every terminated-string assignment voc accepts, so `fileName :=
     name` from voc programs works, and needs no change to what poc's own source
     does.
   - *voc's rule* (whole array by size, `LEN(e) <= LEN(v)`, trap by length; any
     element type): compatible with voc's *generated behavior*, but it traps on
     valid terminated strings and copies the bytes after the terminator.
4. **Other array types: no.** Nothing surveyed needs it, and a partial copy
   leaves the destination's tail undefined; revisit only for a concrete use.
