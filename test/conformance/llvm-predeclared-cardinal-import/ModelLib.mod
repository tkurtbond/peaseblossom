MODULE ModelLib;
  IMPORT WidthTypes;
  CONST
    byteTop* = MAX(SHORTCARD);
    wordTop* = MAX(CARDINAL);
    longTop* = MAX(LONGCARD);
    hugeTop* = MAX(HUGECARD);
    five* = VAL(CARDINAL, 5);
    typed* = VAL(WidthTypes.Word, 5);
    again* = WidthTypes.seven;
  TYPE
    Pair* = RECORD first*: CARDINAL; second*: HUGECARD END;
    Convert* = PROCEDURE(c: CARDINAL): LONGCARD;
  VAR count*: CARDINAL;
  PROCEDURE Widen*(c: CARDINAL): LONGCARD;
  BEGIN
    count := count + 1;
    RETURN LONG(c) + 1
  END Widen;
END ModelLib.
