MODULE VaxPredeclared;
  (* PLAN.md Phase 15 step 7: the predeclared functions of the slice, and
     HALT (the design's section 8). A call whose value is constant is
     folded, LEN of a fixed array among them, so these have variable
     arguments. ABS moves and negates when the move sets N; ODD clears all
     but the low bit of the low byte, BICB3; CHR is CVTxB, the low byte;
     ORD of a CHAR is MOVZBW, of a SET its low word, CVTLW; CAP subtracts
     32 from "a" to "z"; HALT calls POC_HALT. *)

  VAR words: ARRAY 4 OF INTEGER; i: INTEGER; c: CHAR; b: BOOLEAN;

  PROCEDURE AbsB(x: SHORTINT): SHORTINT;
  BEGIN RETURN ABS(x)
  END AbsB;

  PROCEDURE AbsW(x: INTEGER): INTEGER;
  BEGIN RETURN ABS(x)
  END AbsW;

  PROCEDURE AbsL(x: LONGINT): LONGINT;
  BEGIN RETURN ABS(x)
  END AbsL;

  PROCEDURE AbsQ(x: HUGEINT; VAR result: HUGEINT);
  BEGIN result := ABS(x)
  END AbsQ;

  PROCEDURE OddW(x: INTEGER): BOOLEAN;
  BEGIN RETURN ODD(x)
  END OddW;

  PROCEDURE OddQ(x: HUGEINT): BOOLEAN;
  BEGIN RETURN ODD(x)
  END OddQ;

  PROCEDURE OddElement(k: INTEGER): BOOLEAN;
  BEGIN RETURN ODD(words[k])
  END OddElement;

  PROCEDURE ChrW(x: INTEGER): CHAR;
  BEGIN RETURN CHR(x)
  END ChrW;

  PROCEDURE ChrQ(x: HUGEINT): CHAR;
  BEGIN RETURN CHR(x)
  END ChrQ;

  PROCEDURE OrdC(x: CHAR): INTEGER;
  BEGIN RETURN ORD(x)
  END OrdC;

  PROCEDURE OrdS(x: SET): INTEGER;
  BEGIN RETURN ORD(x)
  END OrdS;

  PROCEDURE Cap(x: CHAR): CHAR;
  BEGIN RETURN CAP(x)
  END Cap;

  PROCEDURE Stop;
  BEGIN HALT(7)
  END Stop;

BEGIN
  i := ABS(words[i]);
  c := CAP(c);
  b := ODD(i) & (ORD(c) > 64);
  i := LEN(words)
END VaxPredeclared.
