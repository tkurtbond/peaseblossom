MODULE selfimport;
  (* Oberon2.pdf §11: "A module must not import itself." *)
  IMPORT selfimport;
END selfimport.
