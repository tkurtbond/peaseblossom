MODULE prompt;
  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.11, proposal 2): a prompt written by Out without Ln, then a number
     read by In. With SYS$INPUT a file, the prompt is not given to $GET: it
     stays in Out's line, and the number is written after it, on one line,
     "count? 42". With SYS$INPUT and SYS$OUTPUT terminals, it is $GET's
     prompt instead (checked by hand). *)
  IMPORT In, Out;
  VAR i: INTEGER;
BEGIN
  Out.String("count? "); In.Int(i); Out.Int(i, 0); Out.Ln
END prompt.
