MODULE VaxIncDec;
  (* PLAN.md Phase 15 step 7: INC and DEC, v := v + n and v - n at v's
     width, in place (the design's section 8): INCx and DECx for 1, ADDx2
     and SUBx2 otherwise, ADDL2/ADWC and SUBL2/SBWC for a HUGEINT. A
     narrower n is sign-extended; a wider one gives its low bytes, CVTxy,
     and a constant is wrapped to v's width, so that the sum wraps there as
     all integer arithmetic does. A value parameter INC changes is copied
     to the frame on entry, as one assigned to is. *)

  VAR words: ARRAY 4 OF INTEGER;

  PROCEDURE Up(VAR b: SHORTINT; VAR i: INTEGER; VAR l: LONGINT; VAR h: HUGEINT);
  BEGIN INC(b); INC(i); INC(l); INC(h)
  END Up;

  PROCEDURE Down(VAR b: SHORTINT; VAR i: INTEGER; VAR l: LONGINT; VAR h: HUGEINT);
  BEGIN DEC(b); DEC(i); DEC(l); DEC(h)
  END Down;

  PROCEDURE AddWide(VAR b: SHORTINT; n: LONGINT);
  BEGIN INC(b, n)
  END AddWide;

  PROCEDURE AddConstant(VAR b: SHORTINT);
  BEGIN INC(b, 300)
  END AddConstant;

  PROCEDURE AddNarrow(VAR h: HUGEINT; n: INTEGER);
  BEGIN INC(h, n)
  END AddNarrow;

  PROCEDURE SubHuge(VAR l: LONGINT; h: HUGEINT);
  BEGIN DEC(l, h)
  END SubHuge;

  PROCEDURE Element(k, n: INTEGER);
  BEGIN INC(words[k], n)
  END Element;

  PROCEDURE Next(n: INTEGER): INTEGER;
  BEGIN INC(n, 10); RETURN n
  END Next;

END VaxIncDec.
