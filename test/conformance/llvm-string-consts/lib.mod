MODULE lib;
  (* Library half of llvm-string-consts: an exported and an unexported
     named STRING CONST, to prove a constant's text reaches an importer
     through lib.sym and that the importer's own copy of it is emitted
     by the importer, not looked up in lib's object code. *)
  CONST
    Greeting* = "hello";
    Initial* = "h";
    Hidden = "secret";
  VAR
    probe*: ARRAY 8 OF CHAR;
BEGIN
  COPY(Hidden, probe)
END lib.
