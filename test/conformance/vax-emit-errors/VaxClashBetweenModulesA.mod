MODULE VaxClashBetweenModulesA;
  (* PLAN.md Phase 15 step 8 (the design's section 5.1): a name of this
     module and one it imports from VaxClashBetweenModulesB have the same
     VAX symbol - both modules' names shorten to one stem, and the two
     names' hashes collide - so the clash is an error naming both, found
     while this module is written, and nothing is written, not even
     VaxClashBetweenModulesB.mar *)
  IMPORT B := VaxClashBetweenModulesB;
  VAR clashcQfgBVxgojQf: INTEGER;
BEGIN
  clashcQfgBVxgojQf := B.clashfHvJRlcQIjum
END VaxClashBetweenModulesA.
