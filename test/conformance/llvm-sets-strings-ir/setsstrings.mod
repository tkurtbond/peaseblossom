MODULE setsstrings;
  (* PLAN.md Phase 9 step 3's golden-IR fixture: the exact instruction
     shapes for a SET constructor (single element, range, non-constant
     elements of a narrower and a wider integer type than the SET), IN
     with its range guard, INCL/EXCL; a named STRING CONST reaching a
     call, COPY, an assignment and a comparison (its global appears once
     however often it is used); character-array comparison, and COPY
     from an array - and, at the bottom of the file, the two private
     helper functions, emitted only because this program uses them.
     Also handed to clang for real at each word size. *)
  CONST
    greeting = "hi";
    one = "x";
  VAR
    s: SET;
    small: SHORTINT;
    wide: HUGEINT;
    ok: BOOLEAN;
    buf, other: ARRAY 8 OF CHAR;
    ch: CHAR;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  s := {1, 3 .. 5, small, wide};
  ok := small IN s;
  ok := wide IN s;
  INCL(s, 2); EXCL(s, small);
  SysWrite(1, greeting, 2);
  COPY(greeting, buf);
  buf := greeting;
  ok := buf = greeting;
  ok := greeting # "yo";
  ok := buf < other;
  COPY(buf, other);
  ch := one
END setsstrings.
