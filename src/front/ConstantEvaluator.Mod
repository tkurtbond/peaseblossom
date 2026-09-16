MODULE ConstantEvaluator;

  (* Compile-time constant folding (Oberon2.pdf §5, "Constant
     declarations", plus the parts of Appendix A / §8.2 needed to fold a
     ConstExpr's operators over basic-type operands: numeric arithmetic
     and the numeric inclusion hierarchy, BOOLEAN &/OR/~, SET literals
     and set operators, and the six relations). CASE labels and array
     lengths reuse this same Evaluate* once PLAN.md Phase 4/5 need
     constant expressions in those positions too.

     A ConstExpr's only possible leaves are literals, named constants
     (already-evaluated constClass SymbolTable.Objects) and TRUE/FALSE
     (predeclared constClass Objects in SymbolTable.Universe) - never a
     variable, a call, or a selector - so Evaluate* rejects anything else
     as "not a constant expression" rather than trying to partially
     evaluate it.

     On any error, Evaluate* reports it via Diagnostics and returns a
     Value of type Types.Undefined; callers compare against
     Types.Undefined (never against a specific error value) to decide
     whether to suppress further checks on a poisoned result, so one bad
     operand never cascades into a string of unrelated-looking errors.

     Numeral text-to-value conversion also lives here rather than in
     Lexer.Mod, per that module's own header comment: the lexer only
     records a literal's lexeme text (plus its integer isHex flag and its
     real isLongReal flag), leaving interpretation to whichever later
     phase first needs the actual value. *)

  IMPORT SyntaxTree, Types, SymbolTable, Diagnostics, Lexer;

  CONST
    maxSetElement = 31; (* matches voc's default 32-bit SET (AGENTS.md);
                            revisit once Phase 4 models target word size *)

  PROCEDURE ^ EvaluateExpr(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): Types.Value;

  PROCEDURE UndefinedValue(): Types.Value;
    VAR v: Types.Value;
  BEGIN
    NEW(v); v.type := Types.Undefined; v.kind := Types.intValue; v.intVal := 0;
    RETURN v
  END UndefinedValue;

  (* ---- numeral text -> value ---- *)

  PROCEDURE HexDigitValue(ch: CHAR): INTEGER;
  BEGIN
    IF (ch >= "0") & (ch <= "9") THEN RETURN ORD(ch) - ORD("0")
    ELSE RETURN ORD(ch) - ORD("A") + 10
    END
  END HexDigitValue;

  PROCEDURE ParseDecimalInteger(lexeme: ARRAY OF CHAR): LONGINT;
    VAR i: INTEGER; v: LONGINT;
  BEGIN
    v := 0; i := 0;
    WHILE lexeme[i] # 0X DO
      v := v * 10 + (ORD(lexeme[i]) - ORD("0")); INC(i)
    END;
    RETURN v
  END ParseDecimalInteger;

  PROCEDURE ParseHexInteger(lexeme: ARRAY OF CHAR): LONGINT;
    VAR i: INTEGER; v: LONGINT;
  BEGIN
    v := 0; i := 0;
    WHILE (lexeme[i] # 0X) & (lexeme[i] # "H") DO
      v := v * 16 + HexDigitValue(lexeme[i]); INC(i)
    END;
    RETURN v
  END ParseHexInteger;

  PROCEDURE ParseCharConst(lexeme: ARRAY OF CHAR): CHAR;
    VAR i: INTEGER; v: LONGINT;
  BEGIN
    v := 0; i := 0;
    WHILE (lexeme[i] # 0X) & (lexeme[i] # "X") DO
      v := v * 16 + HexDigitValue(lexeme[i]); INC(i)
    END;
    RETURN CHR(v)
  END ParseCharConst;

  PROCEDURE ParseReal(lexeme: ARRAY OF CHAR): LONGREAL;
    VAR i, expValue: INTEGER; v, scale: LONGREAL; negExp: BOOLEAN;
  BEGIN
    i := 0; v := 0.0;
    WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
      v := v * 10.0 + (ORD(lexeme[i]) - ORD("0")); INC(i)
    END;
    IF lexeme[i] = "." THEN
      INC(i); scale := 0.1;
      WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
        v := v + (ORD(lexeme[i]) - ORD("0")) * scale;
        scale := scale / 10.0; INC(i)
      END
    END;
    IF (lexeme[i] = "E") OR (lexeme[i] = "D") THEN
      INC(i); negExp := FALSE;
      IF lexeme[i] = "-" THEN negExp := TRUE; INC(i)
      ELSIF lexeme[i] = "+" THEN INC(i)
      END;
      expValue := 0;
      WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
        expValue := expValue * 10 + (ORD(lexeme[i]) - ORD("0")); INC(i)
      END;
      IF negExp THEN
        WHILE expValue > 0 DO v := v / 10.0; DEC(expValue) END
      ELSE
        WHILE expValue > 0 DO v := v * 10.0; DEC(expValue) END
      END
    END;
    RETURN v
  END ParseReal;

  PROCEDURE EvaluateLiteral(expr: SyntaxTree.LiteralExprNode): Types.Value;
    VAR v: Types.Value;
  BEGIN
    NEW(v);
    IF expr.literalKind = Lexer.integer THEN
      v.kind := Types.intValue; v.type := Types.Integer;
      IF expr.isHex THEN v.intVal := ParseHexInteger(expr.lexeme)
      ELSE v.intVal := ParseDecimalInteger(expr.lexeme)
      END
    ELSIF expr.literalKind = Lexer.real THEN
      v.kind := Types.realValue;
      IF expr.isLongReal THEN v.type := Types.LongReal ELSE v.type := Types.Real END;
      v.realVal := ParseReal(expr.lexeme)
    ELSIF expr.literalKind = Lexer.charConst THEN
      v.kind := Types.charValue; v.type := Types.Char;
      v.charVal := ParseCharConst(expr.lexeme)
    ELSE (* Lexer.string; also covers a single-quoted single character -
            treating that as CHAR-compatible is deferred, see header *)
      v.kind := Types.stringValue; v.type := Types.String;
      COPY(expr.lexeme, v.stringVal)
    END;
    RETURN v
  END EvaluateLiteral;

  PROCEDURE EvaluateDesignator(expr: SyntaxTree.DesignatorExprNode;
                               scope: SymbolTable.Scope): Types.Value;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator;
  BEGIN
    d := expr.designator;
    IF (d.qualifier[0] # 0X) OR (d.selectors # NIL) OR expr.hasParens THEN
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      RETURN UndefinedValue()
    END;
    obj := SymbolTable.Find(scope, d.name);
    IF obj = NIL THEN
      Diagnostics.Error(expr.line, expr.column, "undeclared identifier");
      RETURN UndefinedValue()
    ELSIF obj.class # SymbolTable.constClass THEN
      Diagnostics.Error(expr.line, expr.column, "not a constant");
      RETURN UndefinedValue()
    ELSE
      RETURN obj.value
    END
  END EvaluateDesignator;

  PROCEDURE EvaluateUnary(expr: SyntaxTree.UnaryExprNode;
                          scope: SymbolTable.Scope): Types.Value;
    VAR v, result: Types.Value;
  BEGIN
    v := EvaluateExpr(expr.operand, scope);
    IF v.type = Types.Undefined THEN RETURN v END;
    IF expr.op = Lexer.minus THEN
      IF Types.IsNumeric(v.type) THEN
        NEW(result); result.type := v.type; result.kind := v.kind;
        IF v.kind = Types.intValue THEN result.intVal := -v.intVal
        ELSE result.realVal := -v.realVal
        END;
        RETURN result
      ELSIF v.type = Types.Set THEN
        NEW(result); result.type := Types.Set; result.kind := Types.setValue;
        result.setVal := {0 .. maxSetElement} - v.setVal;
        RETURN result
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operand of unary '-' must be numeric or a SET");
        RETURN UndefinedValue()
      END
    ELSIF expr.op = Lexer.tilde THEN
      IF v.type # Types.Boolean THEN
        Diagnostics.Error(expr.line, expr.column, "operand of '~' must be BOOLEAN");
        RETURN UndefinedValue()
      END;
      NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
      result.boolVal := ~v.boolVal;
      RETURN result
    ELSE
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      RETURN UndefinedValue()
    END
  END EvaluateUnary;

  PROCEDURE AsReal(v: Types.Value): LONGREAL;
  BEGIN
    IF v.kind = Types.intValue THEN RETURN v.intVal ELSE RETURN v.realVal END
  END AsReal;

  PROCEDURE EvaluateNumericOp(op: INTEGER; l, r: Types.Value): Types.Value;
    VAR result: Types.Value; resultType: Types.Type;
  BEGIN
    resultType := Types.WiderOf(l.type, r.type);
    NEW(result); result.type := resultType;
    IF Types.Rank(resultType) <= Types.hugeIntRank THEN
      result.kind := Types.intValue;
      IF op = Lexer.plus THEN result.intVal := l.intVal + r.intVal
      ELSIF op = Lexer.minus THEN result.intVal := l.intVal - r.intVal
      ELSE result.intVal := l.intVal * r.intVal
      END
    ELSE
      result.kind := Types.realValue;
      IF op = Lexer.plus THEN result.realVal := AsReal(l) + AsReal(r)
      ELSIF op = Lexer.minus THEN result.realVal := AsReal(l) - AsReal(r)
      ELSE result.realVal := AsReal(l) * AsReal(r)
      END
    END;
    RETURN result
  END EvaluateNumericOp;

  PROCEDURE EvaluateDivide(l, r: Types.Value; line, column: INTEGER): Types.Value;
    VAR result: Types.Value;
  BEGIN
    IF AsReal(r) = 0.0 THEN
      Diagnostics.Error(line, column, "division by zero");
      RETURN UndefinedValue()
    END;
    NEW(result); result.kind := Types.realValue;
    IF Types.Rank(Types.WiderOf(l.type, r.type)) = Types.longRealRank THEN
      result.type := Types.LongReal
    ELSE
      result.type := Types.Real
    END;
    result.realVal := AsReal(l) / AsReal(r);
    RETURN result
  END EvaluateDivide;

  PROCEDURE EvaluateIntDivMod(op: INTEGER; l, r: Types.Value;
                              line, column: INTEGER): Types.Value;
    VAR result: Types.Value;
  BEGIN
    IF r.intVal = 0 THEN
      Diagnostics.Error(line, column, "division by zero");
      RETURN UndefinedValue()
    END;
    NEW(result); result.type := Types.WiderOf(l.type, r.type); result.kind := Types.intValue;
    IF op = Lexer.divKeyword THEN result.intVal := l.intVal DIV r.intVal
    ELSE result.intVal := l.intVal MOD r.intVal
    END;
    RETURN result
  END EvaluateIntDivMod;

  PROCEDURE EvaluateSetOp(op: INTEGER; l, r: Types.Value): Types.Value;
    VAR result: Types.Value;
  BEGIN
    NEW(result); result.type := Types.Set; result.kind := Types.setValue;
    IF op = Lexer.plus THEN result.setVal := l.setVal + r.setVal
    ELSIF op = Lexer.minus THEN result.setVal := l.setVal - r.setVal
    ELSIF op = Lexer.times THEN result.setVal := l.setVal * r.setVal
    ELSE result.setVal := l.setVal / r.setVal
    END;
    RETURN result
  END EvaluateSetOp;

  PROCEDURE EvaluateEquality(op: INTEGER; l, r: Types.Value;
                             line, column: INTEGER): Types.Value;
    VAR result: Types.Value; eq: BOOLEAN;
  BEGIN
    IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
      eq := AsReal(l) = AsReal(r)
    ELSIF (l.type = Types.Char) & (r.type = Types.Char) THEN
      eq := l.charVal = r.charVal
    ELSIF (l.type = Types.Boolean) & (r.type = Types.Boolean) THEN
      eq := l.boolVal = r.boolVal
    ELSIF (l.type = Types.Set) & (r.type = Types.Set) THEN
      eq := l.setVal = r.setVal
    ELSIF (l.type = Types.String) & (r.type = Types.String) THEN
      eq := l.stringVal = r.stringVal
    ELSE
      Diagnostics.Error(line, column, "operands are not comparable");
      RETURN UndefinedValue()
    END;
    NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
    IF op = Lexer.notEqual THEN result.boolVal := ~eq ELSE result.boolVal := eq END;
    RETURN result
  END EvaluateEquality;

  PROCEDURE EvaluateOrder(op: INTEGER; l, r: Types.Value;
                          line, column: INTEGER): Types.Value;
    VAR result: Types.Value; lt, le, gt, ge: BOOLEAN;
  BEGIN
    IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
      lt := AsReal(l) < AsReal(r); le := AsReal(l) <= AsReal(r);
      gt := AsReal(l) > AsReal(r); ge := AsReal(l) >= AsReal(r)
    ELSIF (l.type = Types.Char) & (r.type = Types.Char) THEN
      lt := l.charVal < r.charVal; le := l.charVal <= r.charVal;
      gt := l.charVal > r.charVal; ge := l.charVal >= r.charVal
    ELSIF (l.type = Types.String) & (r.type = Types.String) THEN
      lt := l.stringVal < r.stringVal; le := l.stringVal <= r.stringVal;
      gt := l.stringVal > r.stringVal; ge := l.stringVal >= r.stringVal
    ELSE
      Diagnostics.Error(line, column, "operands are not ordered");
      RETURN UndefinedValue()
    END;
    NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
    IF op = Lexer.less THEN result.boolVal := lt
    ELSIF op = Lexer.lessEqual THEN result.boolVal := le
    ELSIF op = Lexer.greater THEN result.boolVal := gt
    ELSE result.boolVal := ge
    END;
    RETURN result
  END EvaluateOrder;

  PROCEDURE EvaluateBinary(expr: SyntaxTree.BinaryExprNode;
                           scope: SymbolTable.Scope): Types.Value;
    VAR l, r, result: Types.Value;
  BEGIN
    l := EvaluateExpr(expr.left, scope); r := EvaluateExpr(expr.right, scope);
    IF (l.type = Types.Undefined) OR (r.type = Types.Undefined) THEN
      RETURN UndefinedValue()
    END;
    IF (expr.op = Lexer.plus) OR (expr.op = Lexer.minus) OR (expr.op = Lexer.times) THEN
      IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
        result := EvaluateNumericOp(expr.op, l, r)
      ELSIF (l.type = Types.Set) & (r.type = Types.Set) THEN
        result := EvaluateSetOp(expr.op, l, r)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands must both be numeric or both SET");
        result := UndefinedValue()
      END
    ELSIF expr.op = Lexer.slash THEN
      IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
        result := EvaluateDivide(l, r, expr.line, expr.column)
      ELSIF (l.type = Types.Set) & (r.type = Types.Set) THEN
        result := EvaluateSetOp(expr.op, l, r)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands must both be numeric or both SET");
        result := UndefinedValue()
      END
    ELSIF (expr.op = Lexer.divKeyword) OR (expr.op = Lexer.modKeyword) THEN
      IF Types.IsInteger(l.type) & Types.IsInteger(r.type) THEN
        result := EvaluateIntDivMod(expr.op, l, r, expr.line, expr.column)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands of DIV/MOD must be integer types");
        result := UndefinedValue()
      END
    ELSIF (expr.op = Lexer.ampersand) OR (expr.op = Lexer.orKeyword) THEN
      IF (l.type = Types.Boolean) & (r.type = Types.Boolean) THEN
        NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
        IF expr.op = Lexer.ampersand THEN result.boolVal := l.boolVal & r.boolVal
        ELSE result.boolVal := l.boolVal OR r.boolVal
        END
      ELSE
        Diagnostics.Error(expr.line, expr.column, "operands of '&'/OR must be BOOLEAN");
        result := UndefinedValue()
      END
    ELSIF (expr.op = Lexer.equal) OR (expr.op = Lexer.notEqual) THEN
      result := EvaluateEquality(expr.op, l, r, expr.line, expr.column)
    ELSIF (expr.op = Lexer.less) OR (expr.op = Lexer.lessEqual)
        OR (expr.op = Lexer.greater) OR (expr.op = Lexer.greaterEqual) THEN
      result := EvaluateOrder(expr.op, l, r, expr.line, expr.column)
    ELSIF expr.op = Lexer.inKeyword THEN
      IF (l.kind = Types.intValue) & (r.type = Types.Set) THEN
        NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
        result.boolVal := SHORT(l.intVal) IN r.setVal
      ELSE
        Diagnostics.Error(expr.line, expr.column, "IN requires an integer and a SET");
        result := UndefinedValue()
      END
    ELSE (* Lexer.isKeyword: a runtime type test, never a constant expression *)
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      result := UndefinedValue()
    END;
    RETURN result
  END EvaluateBinary;

  PROCEDURE EvaluateSet(expr: SyntaxTree.SetExprNode;
                        scope: SymbolTable.Scope): Types.Value;
    VAR result, low, high: Types.Value; el: SyntaxTree.SetElementNode;
        lowVal, highVal, i: LONGINT; ok: BOOLEAN;
  BEGIN
    NEW(result); result.type := Types.Set; result.kind := Types.setValue; result.setVal := {};
    el := expr.elements;
    WHILE el # NIL DO
      low := EvaluateExpr(el.low, scope);
      ok := (low.type # Types.Undefined) & (low.kind = Types.intValue);
      IF (low.type # Types.Undefined) & (low.kind # Types.intValue) THEN
        Diagnostics.Error(el.line, el.column, "set element must be an integer constant")
      END;
      highVal := 0;
      IF ok THEN
        lowVal := low.intVal;
        IF el.high # NIL THEN
          high := EvaluateExpr(el.high, scope);
          IF (high.type # Types.Undefined) & (high.kind = Types.intValue) THEN
            highVal := high.intVal
          ELSE
            IF high.type # Types.Undefined THEN
              Diagnostics.Error(el.line, el.column, "set element must be an integer constant")
            END;
            ok := FALSE
          END
        ELSE
          highVal := lowVal
        END
      END;
      IF ok & ((lowVal < 0) OR (highVal > maxSetElement)) THEN
        Diagnostics.Error(el.line, el.column, "set element out of range 0..31");
        ok := FALSE
      END;
      IF ok THEN
        i := lowVal;
        WHILE i <= highVal DO INCL(result.setVal, SHORT(i)); INC(i) END
      END;
      el := el.next
    END;
    RETURN result
  END EvaluateSet;

  PROCEDURE EvaluateExpr(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): Types.Value;
    VAR v: Types.Value;
  BEGIN
    IF expr = NIL THEN RETURN UndefinedValue() END;
    WITH
      expr: SyntaxTree.LiteralExprNode DO v := EvaluateLiteral(expr)
    | expr: SyntaxTree.DesignatorExprNode DO v := EvaluateDesignator(expr, scope)
    | expr: SyntaxTree.UnaryExprNode DO v := EvaluateUnary(expr, scope)
    | expr: SyntaxTree.BinaryExprNode DO v := EvaluateBinary(expr, scope)
    | expr: SyntaxTree.SetExprNode DO v := EvaluateSet(expr, scope)
    | expr: SyntaxTree.NilExprNode DO
        Diagnostics.Error(expr.line, expr.column, "NIL is not a valid constant expression");
        v := UndefinedValue()
    ELSE
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      v := UndefinedValue()
    END;
    RETURN v
  END EvaluateExpr;

  (* The sole exported entry point; kept a thin wrapper around the
     forward-declared EvaluateExpr so that name, not this one, carries the
     mutual recursion with EvaluateUnary/EvaluateBinary/EvaluateSet above -
     avoids any question of whether an export mark belongs on a forward
     declaration's IdentDef, its completing definition, or both. *)
  PROCEDURE Evaluate*(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): Types.Value;
  BEGIN
    RETURN EvaluateExpr(expr, scope)
  END Evaluate;

END ConstantEvaluator.
