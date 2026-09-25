MODULE client;
  (* Oberon2.pdf only, though what it imports is not: -strict checks this
     module's own text, and an import's .sym or source is exempt. *)
  IMPORT extensions;
BEGIN
  extensions.Bump;
  IF extensions.count > 1 THEN extensions.count := 0 END
END client.
