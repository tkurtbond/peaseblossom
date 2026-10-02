MODULE Greeter;
  (* the module whose commands commands.mod finds by name: Hello and Bye
     are commands; Twice (a parameter), Count (a result), Hidden (not
     exported) and the type-bound Rec.Show are not *)
  IMPORT Out;
  TYPE Rec* = RECORD END;
  VAR calls*: INTEGER;
  PROCEDURE Hello*; BEGIN INC(calls); Out.String("Hello from Greeter"); Out.Ln END Hello;
  PROCEDURE Twice*(n: INTEGER); BEGIN calls := 2 * n END Twice;
  PROCEDURE Count*(): INTEGER; BEGIN RETURN calls END Count;
  PROCEDURE Hidden; BEGIN INC(calls) END Hidden;
  PROCEDURE (VAR r: Rec) Show*; BEGIN Out.String("Rec") END Show;
  PROCEDURE Bye*; BEGIN INC(calls); Out.String("Bye from Greeter"); Out.Ln END Bye;
BEGIN Hidden; calls := 0
END Greeter.
