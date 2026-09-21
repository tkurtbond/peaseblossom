MODULE client;
  (* an importer: the exported view names an imported type as Module.Type,
     and lists the IMPORT; -show-interface needs the imports' .sym files, as
     -emit-interface does (shapes.sym is written just before) *)
  IMPORT shapes;
  TYPE Holder* = RECORD item*: shapes.Shape; note: INTEGER END;
  PROCEDURE Use*(h: Holder): shapes.Shape;
  BEGIN RETURN h.item END Use;
END client.
