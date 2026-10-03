MODULE Report;
  (* Out writes to standard output, Err to standard error *)
  IMPORT Out, Err;
BEGIN
  Out.String("a result"); Out.Ln;
  Err.String("a warning"); Err.Ln
END Report.
