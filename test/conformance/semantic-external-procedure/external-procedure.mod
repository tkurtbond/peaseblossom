MODULE externalProcedure;
  (* AGENTS.md's "External procedures": the decided bracket-attribute
     syntax - a bare "C" convention using the procedure's own Oberon
     identifier as the external symbol, and an overridden external name
     for a symbol that isn't a valid/idiomatic Oberon identifier. *)

  VAR n: INTEGER;

  PROCEDURE ["C"] printf(fmt: ARRAY OF CHAR): INTEGER;
  PROCEDURE ["C", "malloc"] AllocateBytes(size: LONGINT): INTEGER;

BEGIN
  n := printf("hello");
  n := AllocateBytes(8)
END externalProcedure.
