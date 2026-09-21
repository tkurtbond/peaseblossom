MODULE nestedrecursion;
  (* What a call carries along: through mutual recursion (a forward
     declaration closes the cycle), self recursion, a sibling that calls a
     sibling, a child that calls its ancestor, and the enclosing procedure
     itself (an ordinary function, so nothing). *)

  PROCEDURE Helper(k: INTEGER): INTEGER;
  BEGIN RETURN k
  END Helper;

  PROCEDURE Root(n: INTEGER): INTEGER;
    VAR x, y, z: INTEGER;

    PROCEDURE ^ Second(k: INTEGER);
    PROCEDURE ^ Third(k: INTEGER);

    PROCEDURE First(k: INTEGER);
    BEGIN
      x := k;
      IF k > 0 THEN Second(k - 1) END
    END First;

    PROCEDURE Second(k: INTEGER);
    BEGIN
      y := k;
      IF k > 0 THEN Third(k - 1) END
    END Second;

    PROCEDURE Third(k: INTEGER);
    BEGIN
      z := k;
      IF k > 0 THEN First(k - 1) END
    END Third;

    PROCEDURE Countdown(k: INTEGER);
    BEGIN
      IF k > n THEN Countdown(k - 1) END
    END Countdown;

    PROCEDURE CallsRoot;
    BEGIN
      x := Root(0) + Helper(1)
    END CallsRoot;

    PROCEDURE Pong;
    BEGIN INC(n)
    END Pong;

    PROCEDURE Ping;
    BEGIN Pong
    END Ping;

    PROCEDURE Parent;
      PROCEDURE Child;
      BEGIN Ping
      END Child;
    BEGIN Child
    END Parent;

    PROCEDURE Descend(k: INTEGER);
      PROCEDURE Inner;
      BEGIN
        z := k;
        Descend(k - 1)
      END Inner;
    BEGIN
      IF k > 0 THEN Inner END
    END Descend;

  BEGIN
    First(n); Countdown(n); CallsRoot; Parent; Descend(n);
    RETURN x + y + z
  END Root;

BEGIN
END nestedrecursion.
