MODULE Notes;
  (* A file written, registered under its name, then read back *)
  IMPORT Files, Out;
  VAR f: Files.File; r: Files.Rider; line: ARRAY 80 OF CHAR;
BEGIN
  f := Files.New("notes.txt");
  Files.Set(r, f, 0);
  Files.WriteString(r, "first"); Files.WriteString(r, "second");
  Files.Register(f);
  f := Files.Old("notes.txt");
  Files.Set(r, f, 0);
  Files.ReadString(r, line);
  WHILE ~r.eof DO Out.String(line); Out.Ln; Files.ReadString(r, line) END;
  Files.Close(f)
END Notes.
