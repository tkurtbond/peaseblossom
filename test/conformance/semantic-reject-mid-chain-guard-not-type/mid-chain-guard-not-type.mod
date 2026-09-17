MODULE midChainGuardNotType;
  (* Companion to semantic-mid-chain-guard: x is a variable, not a type,
     so "(x)" can't be a mid-chain guard - and unlike a *terminal* v(x)
     (which could still fall back to being read as a one-argument call),
     a guard followed by another selector has no such fallback, since
     Factor's own grammar never lets a call's ActualParameters be
     followed by more selectors (Parser.Mod's TryParseGuardSelector
     header comment). So this is a hard error, not a call
     reinterpretation. *)

  TYPE
    Node = RECORD value: INTEGER END;
    Tree = POINTER TO Node;

  VAR
    t: Tree;
    x: INTEGER;
    v: INTEGER;
BEGIN
  v := t(x).value
END midChainGuardNotType.
