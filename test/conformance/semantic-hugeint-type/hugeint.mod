MODULE hugeInt;
  (* HUGEINT is a Peaseblossom language extension (see Types.Mod's header
     comment, and AGENTS.md's "Vishap Oberon (voc)" section, where it is
     documented as one of voc's own extensions this project chose to
     adopt outright), not part of Oberon2.pdf's own basic types (§6.1).

     This only exercises that HUGEINT resolves as a predeclared type
     identifier and participates in TYPE alias resolution like any other
     basic type. Exercising it as an actual operand's type needs either a
     VAR declaration (PLAN.md Phase 5) or a LONG()-style conversion
     (Phase 6) - neither exists yet, and every integer literal folds to
     type INTEGER regardless of magnitude until Phase 4's MemoryLayout
     work gives basic types real bit widths to check literals against. *)

  TYPE
    Huge = HUGEINT;
BEGIN
END hugeInt.
