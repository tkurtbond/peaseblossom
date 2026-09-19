MODULE client;
  (* PLAN.md Phase 9 step 6: extends and overrides what figures exports,
     and calls back and forth across the module boundary. Each check prints
     "FAIL nn " on failure; the run ends with "OK". *)
  IMPORT figures;
  TYPE
    Box = POINTER TO BoxDesc;
    BoxDesc = RECORD (figures.FigureDesc)
      w, h: INTEGER
    END;
    BigMark = RECORD (figures.Mark)
      extra: INTEGER
    END;
  VAR
    f: figures.Figure; b: Box; own: Box;
    mk: figures.Mark; big: BigMark;
    bp: POINTER TO BigMark;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR text: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      text[0] := "F"; text[1] := "A"; text[2] := "I"; text[3] := "L"; text[4] := " ";
      text[5] := CHR(ORD("0") + number DIV 10); text[6] := CHR(ORD("0") + number MOD 10);
      text[7] := " "; text[8] := 0X;
      SysWrite(1, text, 8)
    END
  END Check;

  (* overrides an exported procedure of an imported record *)
  PROCEDURE (b: Box) Area*(): INTEGER;
  BEGIN RETURN b.w * b.h END Area;

  (* same name as the library's hidden Audit, which cannot be overridden
     from here: a new procedure in a slot of its own *)
  PROCEDURE (b: Box) Audit(): INTEGER;
  BEGIN RETURN 99 END Audit;

  PROCEDURE (b: Box) Perimeter(): INTEGER;
  BEGIN RETURN 2 * (b.w + b.h) END Perimeter;

  PROCEDURE (VAR m: BigMark) Value*(): INTEGER;
  BEGIN RETURN m.n + m.extra END Value;

BEGIN
  (* an object the library made: its own procedures *)
  f := figures.NewFigure(1);
  Check(1, f.Area() = 1);
  Check(2, f.Describe() = 1001);
  Check(3, f.Secret() = 40);

  (* an extension made here, seen through the library's type *)
  NEW(b); b.id := 2; b.w := 3; b.h := 4;
  f := b;
  Check(4, f.Area() = 12);                 (* the importer's override *)
  Check(5, f.Name() = 10);                 (* the library's own *)
  Check(6, f.Describe() = 1012);           (* library code, importer's Area *)
  Check(7, f.Secret() = 0);                (* the library's hidden Audit ... *)
  Check(8, b.Audit() = 99);                (* ... not the importer's *)
  Check(9, b.Perimeter() = 14);
  Check(10, b.Area() = 12);
  Check(11, b.Describe() = 1012);

  (* an extension of a VAR-receiver record *)
  mk.n := 5;
  big.n := 7; big.extra := 100;
  Check(12, mk.Value() = 5);
  Check(13, mk.Double() = 10);
  Check(14, big.Value() = 107);            (* the importer's override *)
  Check(15, big.Double() = 214);           (* library code reaching it *)
  Check(16, figures.Measure(mk) = 6);
  Check(17, figures.Measure(big) = 108);   (* the tag says BigMark *)
  Check(18, figures.ValueOf(big) = 214);
  NEW(bp); bp.n := 1; bp.extra := 2;
  Check(19, bp.Value() = 3);
  Check(20, figures.Measure(bp^) = 4);

  (* an imported variable as a receiver and as a VAR argument *)
  Check(21, figures.current.Area() = 1);
  Check(22, figures.current.Describe() = 1001);
  Check(23, figures.tally.Value() = 21);
  Check(24, figures.tally.Double() = 42);
  Check(25, figures.Measure(figures.tally) = 22);
  figures.current := b;
  Check(26, figures.current.Area() = 12);
  SysWrite(1, "OK", 2)
END client.
