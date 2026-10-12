MODULE Locals;
  (* HUGEINT among a procedure's locals: the backends reopen the body to
     generate it, which must not report it under the importer's -strict *)
  PROCEDURE Twice*(x: INTEGER): INTEGER;
    VAR wide: HUGEINT;
  BEGIN wide := x; RETURN SHORT(SHORT(2 * wide))
  END Twice;
END Locals.
