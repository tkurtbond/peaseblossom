MODULE VaxCopy;
  (* PLAN.md Phase 15 step 7: COPY(x, v), x's characters up to its first
     0X, at most LEN(v) - 1 of them, then 0X (Oberon2.pdf 10.3), the rest
     of v left as it was: one MOVC5 #n, x, #0, #n+1, v. A string constant's
     n is known; an array's is counted by LOCC #0, then limited. An
     address in a register is moved to the frame first, since LOCC and
     MOVC5 overwrite R0-R5. *)

  TYPE Name = ARRAY 8 OF CHAR;

  VAR short: ARRAY 4 OF CHAR; long: ARRAY 16 OF CHAR; name: Name; names: ARRAY 3 OF Name;

  PROCEDURE Constants;
  BEGIN COPY("hello", name); COPY("hello", short); COPY("", long)
  END Constants;

  PROCEDURE Shorten;
  BEGIN COPY(long, short)
  END Shorten;

  PROCEDURE Into(k: INTEGER);
  BEGIN COPY(name, names[k])
  END Into;

  PROCEDURE OutOf(k: INTEGER);
  BEGIN COPY(names[k], long)
  END OutOf;

  PROCEDURE Set(VAR to: Name; from: Name);
  BEGIN COPY(from, to)
  END Set;

END VaxCopy.
