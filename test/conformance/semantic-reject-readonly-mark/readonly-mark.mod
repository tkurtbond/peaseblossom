MODULE readonlyMark;
  (* The "-" read-only export mark is only meaningful on variable and
     record-field declarations (Oberon2.pdf §4: "Variables and record
     fields marked with '-' ... are read-only in importing modules"). *)
  CONST
    x- = 1;
  TYPE
    T- = INTEGER;
BEGIN
END readonlyMark.
