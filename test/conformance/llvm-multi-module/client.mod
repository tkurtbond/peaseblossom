MODULE client;
  (* PLAN.md Phase 8 step 12's dedicated fixture, top (command-line)
     module half - see lib.mod in this same directory for the library
     half and the overall rationale. "Lib" is a deliberately different
     name than the real module ("lib") specifically to exercise the
     alias/realModuleName distinction ResolveQualifiedObject and
     QualifiedName rely on: every generated symbol below must come out
     "@lib.*", never "@Lib.*" or "@client.*". Exercises, in order: a
     qualified ordinary-procedure call with a result (Lib.Add), a
     qualified ordinary-procedure call used as a statement
     (Lib.Accumulate), a qualified VAR read AND a qualified VAR
     assignment target in the same statement (Lib.total := Lib.total +
     1), and (implicitly, via "main"'s own generated call sequence, not
     visible in this source) that lib's own "_init" runs before
     client's own - client's own body reads Lib.total starting from the
     value lib's own BEGIN block gave it (100), not zero. *)
  IMPORT Lib := lib, Out;
  VAR result: INTEGER;
BEGIN
  result := Lib.Add(3, 4);
  Lib.Accumulate(result);
  Lib.total := Lib.total + 1;
  IF (result = 7) & (Lib.total = 108) THEN Out.String("OK") ELSE Out.String("FAIL") END
END client.
