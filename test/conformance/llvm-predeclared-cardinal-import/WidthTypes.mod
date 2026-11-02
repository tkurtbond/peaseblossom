MODULE WidthTypes;
  (* the one module of the fixture that imports SYSTEM *)
  IMPORT SYSTEM;
  TYPE Word* = SYSTEM.CARD16;
  CONST seven* = SYSTEM.VAL(SYSTEM.CARD16, 7);
END WidthTypes.
