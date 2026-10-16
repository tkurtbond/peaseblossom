MODULE Factorial;
  IMPORT SYSTEM, Out, Conditions, DecimalStrings;
  VAR
    product, factor: DecimalStrings.Decimal;
    i: INTEGER;
    status: SYSTEM.INT32;
    text: ARRAY 300 OF CHAR;
BEGIN
  DecimalStrings.FromInteger(1, product);
  i := 2; status := 1;
  WHILE (i <= 50) & Conditions.Succeeded(status) DO
    DecimalStrings.FromInteger(i, factor);
    status := DecimalStrings.Multiply(product, factor, product);
    INC(i)
  END;
  IF Conditions.Succeeded(status) THEN
    DecimalStrings.ToText(product, text)
  ELSE
    Conditions.Message(status, text)
  END;
  Out.String("50! = "); Out.String(text); Out.Ln
END Factorial.
