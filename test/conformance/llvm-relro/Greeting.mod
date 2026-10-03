MODULE Greeting;
  (* llvm-relro: a library of one module, whose shared library must have
     RELRO too *)
  IMPORT Out;
  PROCEDURE Say*;
  BEGIN Out.String("hello, ")
  END Say;
END Greeting.
