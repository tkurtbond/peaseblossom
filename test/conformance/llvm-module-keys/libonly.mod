MODULE libonly;
  (* compiles lib as an imported module, without client, as a library
     will (Phase 12 step 2c): lib.ll then has no main *)
  IMPORT lib;
END libonly.
