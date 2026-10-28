# Arrays whose lengths are run-time values (Phase 19, candidate 6)

Written 2026-10-27, from a question by the user: what would it mean to
allow the lengths in an array declaration to be variables (or any
expression) as well as constants? `Oberon2.pdf` §6.2 makes a length a
constant expression, so this would be an extension. This is an analysis,
not a proposal anyone has adopted, and the survey of other languages
(section 8) is still to do. Nothing here changes poc.

## 1. Two readings

The question has two readings, and they differ a great deal.

1. **A variable's length set at run time.** A procedure's local
   variable, `VAR buf: ARRAY n OF CHAR;`, `n` a parameter or an earlier
   variable, gets its storage on entry, as long as `n` is then. Perhaps an
   unexported module variable too, its length fixed when the module's
   body starts. This is feasible: poc already does the same thing for an
   open-array value parameter (section 2).
2. **A type whose length is a run-time value**: `TYPE Line = ARRAY n OF
   CHAR`, a record field `ARRAY n OF T`, an array of such arrays. This is
   ruled out. A type's size is a compile-time fact everywhere in the
   language and in poc: `SIZE(T)` is a constant; a record's layout gives
   each field a fixed offset; the `.sym` file writes the length; a type
   descriptor holds `size`, which the collector uses to walk an array of
   records (`GarbageCollectedHeap.Mod`, "TRACING"); and an array of `T`
   is indexed by multiplying by a constant. Making any of those a
   run-time value is a different language.

The rest of this note is about reading 1.

## 2. What poc has already

- **The LLVM backend.** An open-array value parameter is copied on
  entry into storage of the run-time length:
  `src/back/llvm/LLVMCodeGenerator.Mod`, about line 7790, emits `alloca
  i8, <bytes>` in the entry block, from the lengths in the dope vector,
  then binds the name with `BindLocalWithDope` and describes it to the
  debugger with `DeclareDebugOpenArray`. A local of run-time length
  would take the same steps, with the lengths computed from its
  declaration instead of read from the caller's dope vector.
- **The collector.** It scans the machine stack conservatively
  (`rtl/llvm/GarbageCollectedHeap.Mod`, line 53): every word on the
  stack that points into a block keeps it alive. So a run-time-length
  local holding pointers needs no stack map or root table, any more than
  the copied parameter does.
- **The VAX backend.** A copied open-array value parameter lives in the
  frame (`inFrameAddress`, `src/back/vax/VaxCodeGenerator.Mod` line
  138): `SUBL2` from SP after the fixed locals, its address and length in
  hidden slots at fixed offsets from FP. A run-time-length local would
  be the same.
- **Every use of an open array**: indexing with its dope vector,
  `LEN(a, d)`, passing to `ARRAY OF T`, and A21's assignment from an open
  source with its length check (exit 9). Typed as an open array, such a
  variable gets all of these for nothing.

## 3. The language decisions it forces

- **When the lengths are evaluated.** Once, on entry, in declaration
  order, before the body; with A23's visibility rule (a variable
  initializer sees only names declared before it), so `VAR n: INTEGER :=
  Count(); buf: ARRAY n OF CHAR;` works and `buf` sees `n`'s
  initialized value. A length is not re-read if `n` changes later.
- **What a length may be.** Any integer expression, as an initializer
  may be. A constant one leaves the array an ordinary fixed one.
- **A length that is not positive.** Trap with exit 7, as `NEW(p, n)`
  does; or allow 0 (an empty array, every index out of range). `NEW`'s
  rule is the consistent one.
- **Its type.** An open array of the element type (`ARRAY OF T`, or
  `ARRAY OF ARRAY OF T` for two run-time dimensions):
  - it can be passed to an `ARRAY OF T` formal, `VAR` or value;
  - passing it to a formal of a fixed array type is an error, as for an
    open-array parameter now (or a run-time length check: a new rule);
  - it can be the source of an assignment to a fixed array, under A21,
    with its length checked (exit 9).
- **As an assignment target.** The one new rule to decide. An open
  array is never an assignment target now (A21). Allowing `buf := s`
  would need a length check the other way (the source no longer than
  `buf`), and strings and `COPY` already cover most uses. Simplest at
  first: not a target, as an open-array parameter is not.
- **Several dimensions.** Each run-time dimension is a dope-vector
  entry, as for a parameter `ARRAY OF ARRAY OF T`; a fixed inner
  dimension (`ARRAY n OF ARRAY 4 OF T`) is folded into the element size
  as now.
- **`LEN` and `SIZE`.** `LEN(a, d)` of a run-time dimension is not a
  constant (the rule "`LEN` of a fixed-length dimension is a constant"
  is unchanged). `SIZE` takes a type, and the variable has no named type,
  so `SIZE` does not apply.
- **Zeroing** (Phase 11 D16, every variable starts at zero). The array
  is cleared on every entry, in time proportional to its length. Only
  programs that use the feature pay it, which fits "cost only for
  users".

## 4. The backends

- **LLVM.** An `alloca` of run-time size in the entry block is what the
  copied parameter does already; LLVM frees it at return. One outside
  the entry block would need `llvm.stacksave`/`llvm.stackrestore`, but
  lengths evaluated on entry keep it in the entry block. The i686 BSDs'
  stack realignment (`LLVMTypes.NeedsStackRealignment`) already copes
  with a dynamic `alloca`, since the copied parameter has one.
  Debug information: `DeclareDebugOpenArray`.
- **VAX.** `SUBL2` the byte count from SP after the fixed locals, round
  to a longword, keep the address and lengths in hidden frame slots, as
  for a copied parameter. The DST debugger records (Phase 18, `-g`) need
  a descriptor-style array record for it, as the copied parameter would.

## 5. Risks

- **Stack exhaustion.** A large length overflows the stack: SIGSEGV on
  the Unix-likes, an access violation on VMS, with no trap message of
  poc's: a worse failure than `NEW`'s NIL or exit 11. The alternative, the heap above a size threshold and
  freed on every exit from the procedure (traps and `HALT` included), is
  much harder and makes the cost depend on the length.
- **Module variables.** Their storage is a global, so a run-time length
  means storage allocated when the module's body starts, before the
  body's statements; a module variable used before that (by an imported
  module's body, through a procedure variable) would see none. Exporting
  one would need the `.sym` file and importers to treat it as an open
  array with a dope vector in the exporting module. Simplest: local
  variables only, or also unexported module variables, never exported.
- **Recursion.** Each activation gets its own copy, as with any local:
  deep recursion with a large `n` reaches the stack's limit sooner.

## 6. How it fits the project

- An extension beyond `Oberon2.pdf`, so `-strict` rejects it, and poc's
  own source cannot use it while voc is the Stage 0 compiler.
- It overlaps with what the language has: `POINTER TO ARRAY OF T` and
  `NEW(p, n)` give an array of run-time length on the heap, with a NIL
  result (or exit 11) instead of a stack overflow, at the cost of an
  allocation and the collector. The new form saves that cost and the
  pointer syntax for short-lived buffers.
- No Oberon dialect is known to have it (to be confirmed by the survey).

## 7. Recommendation, if adopted

Local variables only, perhaps unexported module variables; lengths
evaluated on entry in declaration order, under A23's rules; typed as an
open array; a length that is not positive traps with exit 7; not an
assignment target at first; `-strict` rejects it. Undecided: the user
has not adopted it.

## 8. Survey (to do)

Not done yet. To check, from local sources under
`~/Reference/Computer/Languages/` and `/usr/local/sw/src/lang/Oberon/`
where we have them:

- **The Oberons**: Oberon-07 (Wirth's 2016 report), Component Pascal,
  Active Oberon, voc (`OPP.Mod`, `OPT.Mod`), Oberon+ and the Oakwood
  Guidelines - whether any allows a non-constant length, and how they
  give run-time-sized buffers otherwise.
- **For precedent**:
  - Algol 60's dynamic arrays (`array a[1:n]` in a block), the origin of
    the idea, and Algol 68's;
  - Ada's arrays with bounds from expressions, elaborated on entry, and
    its `Storage_Error` on exhaustion;
  - C99's variable-length arrays, made optional in C11, and why (stack
    exhaustion with no defined failure);
  - Modula-2 (PIM and ISO) and Modula-3, which have open arrays as
    parameters and on the heap (`NEW(REF ARRAY OF T, n)`) but, as far as
    is known, no run-time-length locals.
- For each: where such an array may be declared, when its lengths are
  evaluated, what a bad length does, whether it can be assigned, and
  what running out of stack does.
