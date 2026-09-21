MODULE sameLineTypeUse;
  (* A name used on the same source line it is declared on, to the right of
     its own declaration, is a backward reference and legal. PLAN.md Phase 11
     step 2 (found in Phase 9 step 1): SemanticActions.ResolveQualidentType
     and ConstantEvaluator.LookupBareTypeName compared only the declaration's
     line with the use's, so `A = INTEGER; B = ARRAY 3 OF A;` on one line was
     rejected as "forward reference to a type". Confirmed against real voc
     (2026-09-20): accepts this exact module. The three uses that failed are
     an array element, a record field and a pointer base on the same line as
     the type they name, and SIZE(T) on the line that declares T (ConstantEvaluator's own lookup). *)

  TYPE A = INTEGER; B = ARRAY 3 OF A; R = RECORD f: A; g: B END; P = POINTER TO R;
  TYPE Q = POINTER TO R; S = RECORD next: Q END;
  TYPE T = LONGINT; CONST TSize = SIZE(T); Twice = 2 * TSize; Later = Twice + 1;
  VAR x: A; y: B; z: R; s: S;
BEGIN
  x := 1; y[0] := x; z.f := y[0];
  s.next := NIL
END sameLineTypeUse.
