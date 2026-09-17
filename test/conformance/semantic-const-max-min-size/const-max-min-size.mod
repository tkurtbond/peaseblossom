MODULE constMaxMinSize;
  (* PLAN.md's "Open design questions" (predeclared "functions" in
     constant expressions): MAX(T)/MIN(T)/SIZE(T) are ConstExpr leaves,
     not calls whose argument is a value - their argument position holds
     a bare type name instead. Each assignment below only type-checks if
     the CONST folds to exactly the boundary value/type it claims - a
     narrower/wider inferred type, or a value one off the true boundary,
     would make the assignment fail (mirrors semantic-integer-literal-
     minimal-type's own style, the established project convention for
     pinning down an exact folded value with no runtime ASSERT
     available). Confirmed against real voc (2026-09-17): accepts this
     exact module, and separately rejects MAX(SHORTINT) + 1 assigned to
     a SHORTINT variable (see semantic-reject-const-max-min-too-wide).
     SIZE(T)'s argument is deliberately only ever a *predeclared* basic
     type (INTEGER) here, never a locally-declared RECORD/ARRAY type:
     CheckModuleBody resolves CONST declarations before TYPE
     declarations unconditionally, regardless of their relative textual
     order (the existing "Relax order of declarations" TODO item), so a
     CONST referencing this module's own TYPE section is not yet
     possible - only predeclared/imported types are available yet when
     ConstDecls run. *)

  CONST
    MaxShort = MAX(SHORTINT); MinShort = MIN(SHORTINT);
    MaxInt = MAX(INTEGER); MinInt = MIN(INTEGER);
    MaxLong = MAX(LONGINT); MinLong = MIN(LONGINT);
    MaxHuge = MAX(HUGEINT); MinHuge = MIN(HUGEINT);
    MaxCh = MAX(CHAR); MinCh = MIN(CHAR);
    MaxB = MAX(BOOLEAN); MinB = MIN(BOOLEAN);
    MaxS = MAX(SET);
    IntBytes = SIZE(INTEGER);

  VAR
    short: SHORTINT; int: INTEGER; long: LONGINT; huge: HUGEINT;
    ch: CHAR; b: BOOLEAN; setElem: INTEGER; intSize: INTEGER;
BEGIN
  short := MaxShort; short := MinShort;
  int := MaxInt; int := MinInt;
  long := MaxLong; long := MinLong;
  huge := MaxHuge; huge := MinHuge;
  ch := MaxCh; ch := MinCh;
  b := MaxB; b := MinB;
  setElem := MaxS;
  intSize := IntBytes
END constMaxMinSize.
