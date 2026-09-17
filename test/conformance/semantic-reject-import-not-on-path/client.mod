MODULE client;
  IMPORT Greeter := greeter;

  VAR x: INTEGER;

  PROCEDURE Run;
  BEGIN
    x := Greeter.Greet()
  END Run;

END client.
