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
     supports exactly this save/restore shape with no new API surface.

     Errors go to standard error (Phase 11 D11), as gcc's and clang's do,
     so that a command's own output on standard output (a dump, an
     interface) stays apart from them. *)

  IMPORT Err;

  CONST
    (* room for a path an import-path directory makes, not just a module's
       file name (ModuleInterface.pathBufferLength is 1324) *)
    fileNameLength* = 1399;

  VAR
    errorCount*: INTEGER;
    (* the last error reported, so the same one is not reported twice in a
       row: a variable initializer is checked once for each variable of its
       list (Phase 11 A23), and its errors are the same each time *)
    lastLine, lastColumn: INTEGER;
    lastMessage: ARRAY 400 OF CHAR;
    lastFileName: ARRAY fileNameLength + 1 OF CHAR;
    fileName*: ARRAY fileNameLength + 1 OF CHAR;
    (* poc -strict (Phase 11 B2, decided with the user 2026-09-25): TRUE
       while the module named on the command line is checked, so that
       NotInReport reports each use of a construct beyond Oberon2.pdf in
       its source. FALSE for everything read on its behalf - an imported
       module's source, a .sym file - since what an import uses is not the
       strict module's own text. Here rather than in SemanticActions
       because PredeclaredProcedures, which SemanticActions calls, needs it
       too. *)
    strict*: BOOLEAN;

  PROCEDURE Error*(line, column: INTEGER; message: ARRAY OF CHAR);
  BEGIN
    IF (line = lastLine) & (column = lastColumn) & (message = lastMessage) & (fileName = lastFileName) THEN
      RETURN
    END;
    lastLine := line; lastColumn := column;
    COPY(message, lastMessage); COPY(fileName, lastFileName);
    Err.String(fileName); Err.Char(":");
    Err.Int(line, 0); Err.Char(":"); Err.Int(column, 0);
    Err.String(": error: "); Err.String(message); Err.Ln;
    INC(errorCount)
  END Error;

  (* Under -strict: the construct at line:column, described by what (such
     as "HUGEINT" or "an external procedure"), is poc's extension, not
     Oberon2.pdf's; an error. Otherwise nothing. *)
  PROCEDURE NotInReport*(line, column: INTEGER; what: ARRAY OF CHAR);
    VAR message: ARRAY 256 OF CHAR; i: INTEGER;
    PROCEDURE Append(text: ARRAY OF CHAR);
      VAR k: INTEGER;
    BEGIN
      k := 0;
      WHILE (text[k] # 0X) & (i < LEN(message) - 1) DO message[i] := text[k]; INC(i); INC(k) END;
      message[i] := 0X
    END Append;
  BEGIN
    IF strict THEN
      i := 0; message[0] := 0X;
      Append(what); Append(" is not in the Oberon-2 report (-strict)");
      Error(line, column, message)
    END
  END NotInReport;

  PROCEDURE Reset*(name: ARRAY OF CHAR);
  BEGIN
    (* Appendix A's "assignment compatible" rule 6 only covers a *string
       constant*, not a general ARRAY OF CHAR value (name is an open-array
       formal, not a literal) - real voc accepts "fileName := name" anyway
       as an extension, but poc's own bootstrap-era source must stay
       strict Oberon2.pdf (PLAN.md's "Constraint"), so this uses the
       report's own predeclared COPY instead (§10.3). Found by the Phase 7
       self-check milestone rejecting this exact line. *)
    COPY(name, fileName);
    errorCount := 0
  END Reset;

BEGIN
  errorCount := 0; strict := FALSE;
  fileName := ""
END Diagnostics.
