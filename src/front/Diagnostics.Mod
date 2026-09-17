MODULE Diagnostics;

  (* Error reporting with source positions (line and column are 1-based).
     Reset* records the name of the file currently being compiled so
     every subsequent Error* call can prefix its message with it, matching
     the conventional "file:line:column: error: message" compiler format.
     Warning severity is a natural later addition once multi-file
     compilation (PLAN.md Phase 7) needs it.

     PLAN.md Phase 7 exports fileName* (previously private): while
     SemanticActions.CheckModule recursively resolves an IMPORTed
     module's .sym file, errors inside it must be attributed to that
     .sym file's own name, not the outer module being compiled - but
     Reset* also zeroes errorCount, which must keep accumulating across
     the whole (possibly nested) resolution. Callers doing this save the
     current fileName (COPY, since two independently-declared ARRAY OF
     CHAR locals are not "the same type" and so not `:=`-assignable),
     overwrite it for the nested call, then COPY it back - deliberately
     not a new Reset-like procedure, since a plain exported field already
     supports exactly this save/restore shape with no new API surface. *)

  IMPORT Out;

  CONST
    fileNameLength* = 255;

  VAR
    errorCount*: INTEGER;
    fileName*: ARRAY fileNameLength + 1 OF CHAR;

  PROCEDURE Error*(line, column: INTEGER; message: ARRAY OF CHAR);
  BEGIN
    Out.String(fileName); Out.Char(":");
    Out.Int(line, 0); Out.Char(":"); Out.Int(column, 0);
    Out.String(": error: "); Out.String(message); Out.Ln;
    INC(errorCount)
  END Error;

  PROCEDURE Reset*(name: ARRAY OF CHAR);
  BEGIN
    fileName := name;
    errorCount := 0
  END Reset;

BEGIN
  errorCount := 0;
  fileName := ""
END Diagnostics.
