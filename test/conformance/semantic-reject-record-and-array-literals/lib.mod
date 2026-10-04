MODULE lib;
  TYPE
    Open* = RECORD a*, b*: INTEGER END;
    Hidden* = RECORD a*: INTEGER; secret: INTEGER END;
    ReadOnly* = RECORD a*: INTEGER; b-: INTEGER END;
    Sub* = RECORD (Hidden) c*: INTEGER END;
    Wrap* = RECORD h*: Hidden; n*: INTEGER END;
END lib.
