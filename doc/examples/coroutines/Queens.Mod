MODULE Queens;  (* k queens on an n x n board, one solution at a time *)

  IMPORT Coroutines, Args, In, Out;

  CONST
    maxSize = 26;   (* files a to z *)
    (* modes *)
    askEachTime = 0; firstCount = 1; everySolution = 2;

  VAR
    main, solver: Coroutines.Coroutine;
    n, k: INTEGER;   (* the board's size and the number of queens *)
    column: ARRAY maxSize OF INTEGER;   (* row r's queen's column, -1 if none *)
    columnTaken: ARRAY maxSize OF BOOLEAN;
    upTaken, downTaken: ARRAY 2 * maxSize - 1 OF BOOLEAN;   (* the diagonals *)
    found: BOOLEAN;   (* TRUE: column holds a solution; FALSE: no more *)
    mode: INTEGER;
    count, limit: LONGINT;
    going: BOOLEAN;
    answer: ARRAY 80 OF CHAR;

  (* Wirth's backtracking search, with two changes: a row may be left
     empty while enough rows remain for the queens still to place, and
     each solution is handed to main instead of printed. A row not yet
     given a queen has column -1, and every path puts that back. *)
  PROCEDURE Place(row, placed: INTEGER);
    VAR c: INTEGER;
  BEGIN
    IF placed = k THEN
      found := TRUE; Coroutines.Transfer(solver, main)
    ELSIF n - row >= k - placed THEN
      FOR c := 0 TO n - 1 DO
        IF ~columnTaken[c] & ~upTaken[row + c] & ~downTaken[row - c + n - 1] THEN
          column[row] := c;
          columnTaken[c] := TRUE; upTaken[row + c] := TRUE;
          downTaken[row - c + n - 1] := TRUE;
          Place(row + 1, placed + 1);
          columnTaken[c] := FALSE; upTaken[row + c] := FALSE;
          downTaken[row - c + n - 1] := FALSE;
          column[row] := -1
        END
      END;
      Place(row + 1, placed)   (* and with this row empty *)
    END
  END Place;

  (* The solver's body. It must not return: after the last solution it
     answers every Transfer with "no more". *)
  PROCEDURE Solve;
    VAR r: INTEGER;
  BEGIN
    FOR r := 0 TO n - 1 DO column[r] := -1 END;
    Place(0, 0);
    found := FALSE;
    LOOP Coroutines.Transfer(solver, main) END
  END Solve;

  PROCEDURE NextSolution(): BOOLEAN;
  BEGIN
    Coroutines.Transfer(main, solver);
    RETURN found
  END NextSolution;

  PROCEDURE Rule;
    VAR c: INTEGER;
  BEGIN
    Out.Char("+");
    FOR c := 0 TO n - 1 DO Out.String("---+") END;
    Out.Ln
  END Rule;

  (* The solution's number, its queens' squares in chess notation, and
     the board, the last rank at the top. *)
  PROCEDURE Show(number: LONGINT);
    VAR r, c: INTEGER;
  BEGIN
    Out.String("Solution "); Out.Int(number, 0); Out.Char(":");
    FOR r := 0 TO n - 1 DO
      IF column[r] >= 0 THEN
        Out.Char(" "); Out.Char(CHR(ORD("a") + column[r])); Out.Int(r + 1, 0)
      END
    END;
    Out.Ln;
    FOR r := n - 1 TO 0 BY -1 DO
      Rule; Out.Char("|");
      FOR c := 0 TO n - 1 DO
        IF column[r] = c THEN Out.String(" Q |") ELSE Out.String("   |") END
      END;
      Out.Ln
    END;
    Rule
  END Show;

  PROCEDURE Usage;
  BEGIN
    Out.String("usage: queens [-n size] [-k queens] [all | count]"); Out.Ln;
    Out.String("size 1 to 26, 8 if not given; queens 1 to size, size if not given");
    Out.Ln;
    HALT(2)
  END Usage;

  PROCEDURE Upper(ch: CHAR): CHAR;
  BEGIN
    IF (ch >= "a") & (ch <= "z") THEN ch := CAP(ch) END;
    RETURN ch
  END Upper;

  (* Whether s is word, in either case: DCL passes an argument not in
     quotes in capitals. *)
  PROCEDURE Is(s, word: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (word[i] # 0X) & (Upper(s[i]) = Upper(word[i])) DO INC(i) END;
    RETURN (word[i] = 0X) & (s[i] = 0X)
  END Is;

  (* Argument i as a number from low to high, or the usage message *)
  PROCEDURE Number(i: INTEGER; low, high: LONGINT): LONGINT;
    VAR value: LONGINT;
  BEGIN
    value := low - 1; Args.GetInt(i, value);
    IF (value < low) OR (value > high) THEN Usage END;
    RETURN value
  END Number;

  PROCEDURE ReadArguments;
    VAR i: INTEGER; arg: ARRAY 32 OF CHAR;
  BEGIN
    n := 8; k := 0; mode := askEachTime;
    i := 1;
    WHILE i < Args.argc DO
      Args.Get(i, arg);
      IF Is(arg, "-n") & (i + 1 < Args.argc) THEN
        INC(i); n := SHORT(Number(i, 1, maxSize))
      ELSIF Is(arg, "-k") & (i + 1 < Args.argc) THEN
        INC(i); k := SHORT(Number(i, 1, maxSize))
      ELSIF mode # askEachTime THEN Usage
      ELSIF Is(arg, "all") THEN mode := everySolution
      ELSE mode := firstCount; limit := Number(i, 1, MAX(LONGINT))
      END;
      INC(i)
    END;
    IF k = 0 THEN k := n ELSIF k > n THEN Usage END
  END ReadArguments;

BEGIN
  ReadArguments;
  IF mode = askEachTime THEN In.Open END;
  Out.Int(k, 0); Out.String(" queen");
  IF k > 1 THEN Out.Char("s") END;
  Out.String(" on a "); Out.Int(n, 0); Out.Char("x");
  Out.Int(n, 0); Out.String(" board"); Out.Ln;
  (* The search is at most n + 1 calls of Place deep, below Solve: a
     small stack is plenty. *)
  Coroutines.Init(Solve, 16384, solver);
  count := 0; going := TRUE;
  WHILE going & NextSolution() DO
    INC(count); Show(count);
    CASE mode OF
    | askEachTime:
        Out.String("Another? [Y/n] "); Out.Flush;
        In.Line(answer);
        going := In.Done & (Upper(answer[0]) # "N")
    | firstCount:
        going := count < limit
    | everySolution:
    END
  END;
  IF going THEN
    Out.String("No more: "); Out.Int(count, 0); Out.String(" solutions in all.");
    Out.Ln
  END
END Queens.
