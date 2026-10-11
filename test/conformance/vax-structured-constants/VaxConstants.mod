MODULE VaxConstants;
  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md,
     section 16, proposal 7): structured constants (Phase 14), which the
     VAX backend did not lower: a record with a field of each scalar kind,
     the padding between them and its base's field first; arrays with
     indexed elements and the rest zero; an array of records, nested
     literals without their type's name. Each is data in POC_CONST, used
     as a variable is: assigned, passed by value, to an open array and
     read-only. ConstOut prints what each gives, on both backends, and
     uses them from another module. *)
  IMPORT SYSTEM;
  TYPE
    Base* = RECORD tag*: CHAR END;
    Node* = POINTER TO Base;
    All* = RECORD (Base)
      s*: SHORTINT; i*: INTEGER; l*: LONGINT; h*: HUGEINT; b*: BOOLEAN;
      set*: SET; set64*: SYSTEM.SET64; r*: REAL; lr*: LONGREAL; p*: Node;
      name*: ARRAY 6 OF CHAR
    END;
    Vector* = ARRAY 6 OF INTEGER;
    Point* = RECORD x*, y*: SHORTINT END;
    Grid* = ARRAY 3 OF Point;
  CONST
    all* = All{tag := "T", s := -5, i := -300, l := -70000, h := -5000000000, b := TRUE,
               set := {0, 31}, set64 := {1, 63}, r := 1.5, lr := -2.25, p := NIL, name := "abc"};
    vector* = Vector{[0..1]: 7, [4]: -1};
    grid* = Grid{{x := 1, y := 2}, [2]: {x := -3, y := 4}};

  PROCEDURE CopyAll*(VAR a: All);
  BEGIN a := all
  END CopyAll;

  PROCEDURE Sum*(v: Vector): LONGINT;
    VAR k, total: LONGINT;
  BEGIN
    total := 0; FOR k := 0 TO LEN(v) - 1 DO total := total * 10 + v[k] END;
    RETURN total
  END Sum;

  PROCEDURE SumOpen*(v: ARRAY OF INTEGER): LONGINT;
    VAR k, total: LONGINT;
  BEGIN
    total := 0; FOR k := 0 TO LEN(v) - 1 DO total := total + v[k] END;
    RETURN total
  END SumOpen;

  PROCEDURE Corners*(g-: Grid): LONGINT;
  BEGIN RETURN ((LONG(LONG(g[0].x)) * 10 + g[0].y) * 10 + g[2].x) * 10 + g[2].y
  END Corners;

  PROCEDURE SumVector*(): LONGINT;
  BEGIN RETURN Sum(vector)
  END SumVector;

  PROCEDURE GridCorners*(): LONGINT;
    VAR g: Grid;
  BEGIN g := grid; RETURN Corners(g) + Corners(grid)
  END GridCorners;

END VaxConstants.
