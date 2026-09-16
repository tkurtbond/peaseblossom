MODULE Diagnostics;

  (* Error reporting with source positions (line and column are 1-based).
     Deliberately minimal for Phase 1 (single-file lexing only); a
     filename field and warning severity are natural later additions
     once multi-file compilation (PLAN.md Phase 7) needs them. *)

  IMPORT Out;

  VAR
    errorCount*: INTEGER;

  PROCEDURE Error*(line, column: INTEGER; message: ARRAY OF CHAR);
  BEGIN
    Out.Int(line, 0); Out.Char(":"); Out.Int(column, 0);
    Out.String(": error: "); Out.String(message); Out.Ln;
    INC(errorCount)
  END Error;

  PROCEDURE Reset*;
  BEGIN
    errorCount := 0
  END Reset;

BEGIN
  errorCount := 0
END Diagnostics.
