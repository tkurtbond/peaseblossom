MODULE VaxClashBetweenModulesA;
  (* imported by VaxBuildClash (the design's section 5.1, layer 2): its
     exported variable has the VAX symbol of one VaxClashBetweenModulesB
     exports, though neither module refers to the other; within one run
     the two are an error, not a silent binding at link *)
  VAR clashcQfgBVxgojQf*: INTEGER;
END VaxClashBetweenModulesA.
