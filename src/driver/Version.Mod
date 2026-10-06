MODULE Version;

  (* poc's version (Phase 13 step 1, decided with the user 2026-10-02):
     0.x.y until a release meant for others, the minor number for features,
     the patch number for fixes. Kept here and nowhere else; `poc -version`
     prints it, with the commit of a build from a git checkout
     (BuildInfo.Mod, which make writes into build/gen), and a library's
     manifest records it, so a library another version of poc wrote is
     refused (Libraries.Load): nothing promises that two versions' objects
     link together. *)

  CONST
    number* = "0.4.0";

END Version.
