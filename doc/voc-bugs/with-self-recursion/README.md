# voc bug: self-recursive call from inside a `WITH` branch

**Status**: confirmed, root cause identified, not yet reported upstream.
**Affects**: Vishap Oberon (`voc`) 2.1.0 [2026/09/16] for gcc LP64 on
Fedora, built on Ofront (J. Templ). Source:
`github.com/vishapoberon/compiler.git`, `src/compiler/OPP.Mod`.
**Found while**: writing Peaseblossom's `SemanticActions.ResolveType`
(Phase 3), which recurses into itself from inside a `WITH` branch to
resolve a `POINTER TO`'s base type. See `AGENTS.md` in this repository
for the short version and the workaround actually used there.

## Symptom

A procedure `P` that calls **itself** from inside one of `P`'s own
`WITH v: T DO ... END` branches is miscompiled. Depending on exactly how
the recursive call's argument is written, this shows up in one of two
ways:

1. A bogus front-end **"incompatible assignment"** error (voc's own
   error 113), even when the actual argument's type is *exactly* the
   formal parameter's declared type. See `FalseError.Mod`.
2. No front-end error, but voc emits **wrongly-typed C** for the
   recursive call's argument (a pointer reinterpreted as the wrong
   struct type), which a C compiler with strict pointer-type checking
   (e.g. a recent gcc, where this class of mismatch is a hard error, not
   just a warning) then rejects. See `Miscompile.Mod`.

Calling a *different* procedure from inside the same `WITH` branch is
unaffected in both cases — only literal self-recursion to the enclosing
procedure triggers this.

## Minimal reproductions

`FalseError.Mod` (front-end false positive):

```oberon
TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD END;
  Ptr = POINTER TO PtrDesc;
  PtrDesc = RECORD (BaseDesc)
    base: Base
  END;

PROCEDURE ^ P(node: Base);

PROCEDURE P(node: Base);
BEGIN
  WITH node: Ptr DO
    P(node.base)
  END
END P;
```

`voc -s FalseError.Mod`:

```
FalseError.Mod  Compiling FalseError.

  32:       P(node.base)
                      ^
    pos   962  err 113  incompatible assignment

Module compilation failed.
```

`node.base` is declared as type `Base` — precisely `P`'s own formal
parameter type — so this should compile without comment.

`Miscompile.Mod` (back-end miscompile, same root cause, different
surface): recurses with the guarded variable `node` itself rather than a
field access off it. This passes voc's Oberon-2 front end, but the
generated C casts the argument to the *narrowed* struct type instead of
the formal parameter's declared type:

```
Miscompile.c: In function ‘Miscompile_P’:
Miscompile.c:37:31: error: passing argument 1 of ‘Miscompile_P’ from incompatible pointer type [-Wincompatible-pointer-types]
   37 |                 Miscompile_P((*(Miscompile_Ptr*)&node));
      |                              ~^~~~~~~~~~~~~~~~~~~~~~~~
      |                               |
      |                               Miscompile_Ptr {aka struct Miscompile_PtrDesc *}
Miscompile.c:34:43: note: expected ‘Miscompile_Base’ {aka ‘struct Miscompile_BaseDesc *’} but argument is of type ‘Miscompile_Ptr’
```

Both files in this directory compile cleanly once the `WITH` is removed,
or once the recursive call is moved after the `WITH` statement ends (see
"Workaround" below) — confirming `WITH` plus self-recursion is exactly
the trigger, not some unrelated mistake in the reproduction itself.

## Narrowing it down

A few variations were tried to isolate the exact trigger (not checked in,
described here for anyone verifying this independently):

- `WITH node: Node DO ... P(node) ...` where `Node`'s declared type
  already **is** `Node` (a trivial, non-narrowing guard against a
  self-referential type) — **does not** reproduce. The guard must
  actually *narrow* to a proper extension type.
- Replacing the `WITH` with an equivalent explicit type-test-and-guard,
  `IF node IS Ptr THEN P(node(Ptr).base) END`, using the very same types
  — **does not** reproduce. The bug is specific to voc's `WITH`
  implementation, not to type guards/type tests in general.
- Calling a *different* procedure `Q` from inside `P`'s `WITH` branch,
  where `Q` itself separately calls `P` — **does not** reproduce, even
  though `P` still ends up called "from within" `P`'s own `WITH` branch
  transitively. Only a *literal* `P(...)` call written inside `P`'s own
  `WITH` triggers it.
- Using a plain (non-function) `PROCEDURE`, as in `FalseError.Mod`, vs. a
  function `PROCEDURE ... : INTEGER` with `RETURN P(...)` — both
  reproduce identically. Not specific to function procedures or `RETURN`.

## Root cause

`src/compiler/OPP.Mod`, in `StatSeq`'s `WITH` case (Vishap Oberon compiler
source, `github.com/vishapoberon/compiler.git`):

```oberon
IF sym = OPS.ident THEN qualident(t);
  IF t^.mode = OPT.Typ THEN
    IF id # NIL THEN
      idtyp := id^.typ; OPB.TypTest(y, t, FALSE); id^.typ := t^.typ
    ELSE err(130)
    END
  ...
  END
END ;
pos := OPM.errpos; CheckSym(OPS.do); StatSeq(s); OPB.Construct(OPT.Nif, y, s); SetPos(y);
IF idtyp # NIL THEN id^.typ := idtyp; idtyp := NIL END ;
```

`id` is the guarded variable's **symbol-table Object** — the very same
Object that every other mention of that identifier resolves to,
including the formal-parameter Object consulted when type-checking a
call's actual arguments against it. To implement the guard, this code:

1. Saves the Object's true type (`idtyp := id^.typ`).
2. **Overwrites the Object's type in place** with the narrowed type
   (`id^.typ := t^.typ`) for the duration of the branch body
   (`StatSeq(s)`, the very next statement).
3. Restores the true type afterward (`id^.typ := idtyp`).

This is fine for ordinary uses of the guarded variable within the
branch — that's the entire point of `WITH`. It breaks down specifically
for a **recursive call to the enclosing procedure** made from inside that
same branch: a procedure's formal parameters and its own body share the
*one* Object per parameter, so while `StatSeq(s)` is being compiled, that
Object's `typ` field is *simultaneously* "the narrowed type, for
evaluating expressions naming the guarded variable" and "the formal
parameter type, for checking this recursive call's actual argument" —
and the mutation makes those two conflate:

- In `FalseError.Mod`, the actual argument `node.base` has the true,
  correct type `Base`. But the compatibility check the recursive call
  triggers reads the formal parameter's type off the same Object that
  was just overwritten to `Ptr`, so it checks "is `Base` compatible with
  `Ptr`?" — no, `Base` is the wider type, not an extension of `Ptr` — and
  reports err 113.
- In `Miscompile.Mod`, the actual argument is `node` itself, whose
  *expression* type genuinely is `Ptr` inside the branch. Checked against
  the same overwritten formal-parameter type (`Ptr`), it now matches, so
  no front-end error fires — but the already-guard-cast representation of
  `node` (built for ordinary uses inside the branch) is what gets threaded
  through to the call site's C emission, producing a pointer reinterpreted
  as `Ptr` passed to a parameter C-typed as `Base`.

Calling a *different* procedure avoids all of this because that
procedure's formal parameters are distinct Objects, never touched by this
`WITH`'s save/overwrite/restore.

A fix would need to avoid mutating the shared Object's `typ` field
in place — for example, checking actual arguments against a call's
*declared* signature independently of any in-flight `WITH` narrowing, or
giving the guard a private/shadow type slot instead of overwriting the
canonical Object used by parameter-compatibility checks elsewhere.

## Workaround (used in Peaseblossom)

Do not call the enclosing procedure directly from inside its own `WITH`
branch. Save whatever the recursive call needs into a local variable
inside the branch, then make the call after the `WITH` statement ends:

```oberon
PROCEDURE ResolveType(scope: SymbolTable.Scope; node: SyntaxTree.TypeNode;
                      allowForward: BOOLEAN): Types.Type;
  VAR pointerBase: SyntaxTree.TypeNode;
BEGIN
  IF node = NIL THEN RETURN Types.Undefined END;
  WITH
    node: SyntaxTree.QualidentTypeNode DO
      RETURN ResolveQualidentType(scope, node, allowForward)
  | node: SyntaxTree.PointerTypeNode DO
      pointerBase := node.base
  ELSE
    Diagnostics.Error(node.line, node.column,
      "array, record, and procedure types are not yet implemented");
    RETURN Types.Undefined
  END;
  (* the recursive call is kept outside the WITH above deliberately -
     see doc/voc-bugs/with-self-recursion/README.md *)
  RETURN Types.NewPointerType(ResolveType(scope, pointerBase, TRUE))
END ResolveType;
```

(`src/front/SemanticActions.Mod` in this repository.)
