MODULE notrap;
  (* Phase 11, C9 (AGENTS.md, "What traps, and what does not"): behaviors that
     look like they should stop the program and do not, or that stop it with no
     message, pinned so the table stays true.  One case per run, chosen by the
     program's argument, under both size models.  Nothing here depends on the
     host: division by zero is left out on purpose, being a SIGFPE on x86 and a
     silent 0 on ARM (LLVM's sdiv by zero is undefined).  Cases 11 and 12 die
     by a signal, whichever the host's stack overflow or bad address raises. *)
  IMPORT Modules, Out, SYSTEM;
  TYPE
    RecT = RECORD i: INTEGER; s: SET; p: POINTER TO RecT END;
    Proc = PROCEDURE;
  VAR
    which: LONGINT;
    gi: INTEGER; gl: LONGINT; gb: BOOLEAN; gr: REAL; gs: SET; gp: POINTER TO RecT; gv: Proc;
    garr: ARRAY 4 OF INTEGER; grec: RecT;
    k: INTEGER; n: INTEGER; s: SET; a4: ARRAY 4 OF INTEGER;
    c4: ARRAY 4 OF CHAR; c8, u8, v8: ARRAY 8 OF CHAR; r, z: REAL; addr: SYSTEM.ADDRESS; x: LONGINT;

  PROCEDURE Deep(d: LONGINT);
    VAR pad: ARRAY 64 OF CHAR;
  BEGIN pad[0] := CHR(SHORT(d MOD 100)); Deep(d + 1); Out.Char(pad[0]) END Deep;

  PROCEDURE Count(b: BOOLEAN): INTEGER;
  BEGIN IF b THEN RETURN 1 ELSE RETURN 0 END END Count;

  PROCEDURE LocalPointers;
    VAR p: POINTER TO RecT; v: Proc; rec: RecT;
  BEGIN
    Out.String("local pointer, procedure value, record's pointer field: ");
    Out.Int(Count(p = NIL) + Count(v = NIL) + Count(rec.p = NIL), 0); Out.String(" of 3 are NIL"); Out.Ln
  END LocalPointers;

  PROCEDURE Show(label: ARRAY OF CHAR; b: BOOLEAN);
  BEGIN
    Out.String(label);
    IF b THEN Out.String("TRUE") ELSE Out.String("FALSE") END;
    Out.Ln
  END Show;

BEGIN
  Modules.GetIntArg(1, which);
  CASE which OF
    0: Out.String("module variables start as zero: ");
       Out.Int(gi, 0); Out.Char(" "); Out.Int(gl, 0); Out.Char(" "); Out.Int(ENTIER(gr), 0); Out.Char(" ");
       Out.Int(garr[3], 0); Out.Char(" "); Out.Int(grec.i, 0); Out.Ln;
       Show("BOOLEAN ", gb); Show("SET empty ", gs = {});
       Show("pointer and procedure value NIL ", (gp = NIL) & (gv = NIL) & (grec.p = NIL));
       LocalPointers
  | 1: HALT(3)
  | 2: HALT(0)
  | 3: HALT(255)
  | 4: c8 := "abcdefg"; COPY(c8, c4); Out.String("COPY into a shorter array: "); Out.String(c4); Out.Ln;
       FOR k := 0 TO 7 DO u8[k] := CHR(65 + k) END;
       COPY(u8, c4); Out.String("COPY of an unterminated source: "); Out.String(c4); Out.Ln;
       COPY("", c4); Out.String("COPY of the empty string: ["); Out.String(c4); Out.String("]"); Out.Ln
  | 5: FOR k := 0 TO 7 DO u8[k] := CHR(65 + k); v8[k] := CHR(65 + k) END;
       Show("two equal arrays without a 0X are equal: ", u8 = v8);
       v8[7] := "Z"; Show("ABCDEFGH < ABCDEFGZ: ", u8 < v8);
       Out.String("LEN of an array without a 0X: "); Out.Int(LEN(u8), 0); Out.Ln
  | 6: a4[0] := 5; SYSTEM.MOVE(SYSTEM.ADR(a4), SYSTEM.ADR(garr), -4);
       Out.String("MOVE with a negative count moves nothing: "); Out.Int(garr[0], 0); Out.Ln;
       SYSTEM.MOVE(SYSTEM.ADR(a4), SYSTEM.ADR(garr), 0);
       Out.String("... and so does a count of 0: "); Out.Int(garr[0], 0); Out.Ln
  | 7: s := {0..31};
       n := 32; Show("32 IN {0..31}: ", n IN s);
       n := 40; Show("40 IN {0..31}: ", n IN s);
       n := -1; Show("-1 IN {0..31}: ", n IN s)
  | 8: FOR k := MAX(INTEGER) - 1 TO MAX(INTEGER) DO
         Out.Int(k, 0); Out.Char(" ");
         IF k = MIN(INTEGER) + 3 THEN Out.Ln; Out.String("the loop went on past MAX(INTEGER)"); Out.Ln; HALT(77) END
       END;
       Out.String("the loop ended"); Out.Ln
  | 9: r := 1.0; z := 0.0; r := r / z; Show("REAL 1.0/0.0 survived, is large: ", r > 1.0E30);
       z := z / z; Show("0.0/0.0 survived, is not equal to itself: ", z # z)
  | 11: addr := 0; SYSTEM.GET(addr, x); Out.String("a read at address 0 survived"); Out.Ln
  | 12: Deep(0); Out.String("unbounded recursion returned"); Out.Ln
  END
END notrap.
