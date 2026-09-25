MODULE Late;
  (* Declarations after procedures (doc/language-extensions.md): what
     stays an error. Line 8: a body uses a VAR declared after it. Lines 13
     and 21: a late declaration hides a name visible from an enclosing
     scope (the global i, the predeclared LEN). Line 17: a POINTER TO base
     declared after the next procedure. Lines 22-23: ordinary errors. *)
  VAR i: INTEGER;
  PROCEDURE UsesLater; BEGIN later := 1 END UsesLater;
  VAR later: INTEGER;

  PROCEDURE Outer;
    PROCEDURE Inner; BEGIN i := 2 END Inner;
    VAR i: INTEGER;
  BEGIN Inner
  END Outer;

  TYPE P = POINTER TO R;
  PROCEDURE Between; END Between;
  TYPE R = RECORD END;

  VAR LEN: INTEGER;
  CONST later = 3;
  PROCEDURE UsesBase(q: Base); END UsesBase;
  TYPE Base = RECORD END;
END Late.
