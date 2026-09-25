MODULE Parser;

  (* Recursive-descent parser for Oberon-2 (Oberon2.pdf, Appendix B).
     One private procedure per grammar production, each named to match the
     production it recognizes; SemanticActions.Mod supplies the tree nodes.
     Only ParseModule and the Parser state itself are exported - Poc.Mod's
     driver code never needs the individual production parsers.

     Two deliberate Phase 2 simplifications, both noted where they matter
     below, since resolving them properly needs information this phase
     doesn't have yet (a symbol table, Phase 3's SymbolTable.Mod):

     1. Qualident-vs-selector ambiguity: "a.b" is a qualified identifier
        (module "a", export "b") if "a" names an imported module, and
        otherwise a field/element selection on a plain designator "a".
        Resolved here using only the current module's IMPORT list (already
        fully parsed before any qualident can occur) - correct except when
        a local declaration shadows an import alias, which Phase 3 will
        need to re-check once real scoping exists.

     2. Type-guard-vs-call ambiguity: Designator's own grammar has a
        "(" Qualident ")" selector alternative (an inline type guard, as in
        "t.left(CenterNode).name"), but Factor and Statement separately
        allow a trailing "(" [ExprList] ")" (a call) after any designator -
        the same token can start either, and telling them apart in general
        needs to know whether the designator denotes a procedure or a
        pointer/record variable. PLAN.md Phase 5 resolves this for a
        *terminal* guard/IS once real symbol information exists
        (SemanticActions.Mod's LookupBareTypeName/CheckDesignatorExpr):
        every "(...)" that ends a designator (nothing selector-shaped
        follows) still parses uniformly as call arguments there, and
        semantic checking decides after the fact whether the sole
        argument was really a type name.

        A *mid-chain* guard (t(CenterTree).subnode) needs the parser
        itself to disambiguate, since nothing later ever gets a chance to
        reinterpret a selector that already has more selectors chained
        after it. ParseDesignator's selector loop resolves this
        syntactically, with no symbol-table lookup needed: Factor's own
        grammar (Designator [ActualParameters]) guarantees ActualParameters
        can never be followed by another selector, so whenever "(" Qualident
        ")" is immediately followed by another selector token
        ("." "[" "^" "("), it cannot be anything other than a guard -
        TryParseGuardSelector below commits to a GuardSelector node in
        exactly that situation (checkpointing the parser state and
        rolling back to try ActualParameters instead for every other
        shape: multiple/complex arguments, or a lone Qualident with
        nothing selector-shaped after it, which stays simplification 2's
        existing terminal case, untouched). GuardSelector previously went
        unused for exactly this reason - see AGENTS.md and PLAN.md's
        "Type guards in designators" for the fuller history.

     PLAN.md Phase 6 adds one small, unambiguous grammar addition rather
     than resolving either simplification above: a "[" right after
     PROCEDURE (before any Receiver/IdentDef) introduces the already-
     decided external-procedure-declaration attribute (AGENTS.md,
     "External procedures") - ParseDeclSeq's procedure loop checks for it
     the same way it already checks for "^" (isForward), and
     ParseExternalAttribute parses the "[" string [ "," string ] "]"
     itself. *)

  IMPORT Lexer, Diagnostics, SyntaxTree, SemanticActions;

  TYPE
    Alias = POINTER TO AliasDesc;
    AliasDesc = RECORD
      name: SyntaxTree.Ident;
      next: Alias
    END;

    Parser* = RECORD
      scanner: Lexer.Scanner;
      current: Lexer.Token;
      aliases: Alias (* local names the current module's IMPORT list bound,
                         used to resolve the qualident/selector ambiguity
                         above; see simplification 1 *)
    END;

  PROCEDURE Advance(VAR p: Parser);
  BEGIN
    Lexer.NextToken(p.scanner, p.current)
  END Advance;

  PROCEDURE ExpectToken(VAR p: Parser; kind: INTEGER; message: ARRAY OF CHAR);
  BEGIN
    IF p.current.kind # kind THEN
      Diagnostics.Error(p.current.line, p.current.column, message)
    END;
    Advance(p)
  END ExpectToken;

  PROCEDURE ExpectIdent(VAR p: Parser; VAR name: SyntaxTree.Ident);
  BEGIN
    IF p.current.kind = Lexer.ident THEN
      COPY(p.current.lexeme, name)
    ELSE
      name[0] := 0X;
      Diagnostics.Error(p.current.line, p.current.column, "expected an identifier")
    END;
    Advance(p)
  END ExpectIdent;

  PROCEDURE IsAddOp(kind: INTEGER): BOOLEAN;
  BEGIN
    RETURN (kind = Lexer.plus) OR (kind = Lexer.minus) OR (kind = Lexer.orKeyword)
  END IsAddOp;

  PROCEDURE IsMulOp(kind: INTEGER): BOOLEAN;
  BEGIN
    RETURN (kind = Lexer.times) OR (kind = Lexer.slash)
         OR (kind = Lexer.divKeyword) OR (kind = Lexer.modKeyword)
         OR (kind = Lexer.ampersand)
  END IsMulOp;

  PROCEDURE IsRelation(kind: INTEGER): BOOLEAN;
  BEGIN
    RETURN (kind = Lexer.equal) OR (kind = Lexer.notEqual)
         OR (kind = Lexer.less) OR (kind = Lexer.lessEqual)
         OR (kind = Lexer.greater) OR (kind = Lexer.greaterEqual)
         OR (kind = Lexer.inKeyword) OR (kind = Lexer.isKeyword)
  END IsRelation;

  PROCEDURE IsKnownAlias(VAR p: Parser; name: SyntaxTree.Ident): BOOLEAN;
    VAR a: Alias;
  BEGIN
    a := p.aliases;
    WHILE (a # NIL) & (a.name # name) DO a := a.next END;
    RETURN a # NIL
  END IsKnownAlias;

  PROCEDURE AddAlias(VAR p: Parser; name: SyntaxTree.Ident);
    VAR a: Alias;
  BEGIN
    NEW(a); a.name := name; a.next := p.aliases; p.aliases := a
  END AddAlias;

  PROCEDURE ParseQualident(VAR p: Parser; VAR qualifier, name: SyntaxTree.Ident);
    VAR first: SyntaxTree.Ident;
  BEGIN
    ExpectIdent(p, first);
    IF (p.current.kind = Lexer.period) & IsKnownAlias(p, first) THEN
      Advance(p);
      ExpectIdent(p, name);
      qualifier := first
    ELSE
      qualifier[0] := 0X;
      name := first
    END
  END ParseQualident;

  PROCEDURE ParseIdentDef(VAR p: Parser): SyntaxTree.IdentDefNode;
    VAR name: SyntaxTree.Ident; exportMark: INTEGER; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ExpectIdent(p, name);
    IF p.current.kind = Lexer.times THEN
      exportMark := SyntaxTree.exportPublic; Advance(p)
    ELSIF p.current.kind = Lexer.minus THEN
      exportMark := SyntaxTree.exportReadOnly; Advance(p)
    ELSE
      exportMark := SyntaxTree.exportNone
    END;
    RETURN SemanticActions.NewIdentDef(name, exportMark, line, column)
  END ParseIdentDef;

  PROCEDURE ParseIdentList(VAR p: Parser): SyntaxTree.IdentDefNode;
    VAR head, tail, node: SyntaxTree.IdentDefNode;
  BEGIN
    head := ParseIdentDef(p); tail := head;
    WHILE p.current.kind = Lexer.comma DO
      Advance(p);
      node := ParseIdentDef(p);
      tail.next := node; tail := node
    END;
    RETURN head
  END ParseIdentList;

  (* A formal parameter's names are plain identifiers (Oberon2.pdf 10.1:
     FPSection = [VAR] ident {"," ident} ":" Type), not IdentDefs: an export
     mark after one is reported and skipped, so the rest of the section still
     parses. voc reads "x-" as a read-only VAR parameter (Oakwood 5.13, which
     recommends against it); poc does not have them, see
     doc/language-extensions.md, "Read-only parameters". *)
  PROCEDURE ParseParamName(VAR p: Parser): SyntaxTree.IdentDefNode;
    VAR name: SyntaxTree.Ident; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ExpectIdent(p, name);
    IF (p.current.kind = Lexer.times) OR (p.current.kind = Lexer.minus) THEN
      Diagnostics.Error(p.current.line, p.current.column,
        "a formal parameter cannot have an export mark");
      Advance(p)
    END;
    RETURN SemanticActions.NewIdentDef(name, SyntaxTree.exportNone, line, column)
  END ParseParamName;

  PROCEDURE ParseParamNames(VAR p: Parser): SyntaxTree.IdentDefNode;
    VAR head, tail, node: SyntaxTree.IdentDefNode;
  BEGIN
    head := ParseParamName(p); tail := head;
    WHILE p.current.kind = Lexer.comma DO
      Advance(p);
      node := ParseParamName(p);
      tail.next := node; tail := node
    END;
    RETURN head
  END ParseParamNames;

  PROCEDURE ^ ParseExpr(VAR p: Parser): SyntaxTree.ExprNode;
  PROCEDURE ^ ParseType(VAR p: Parser): SyntaxTree.TypeNode;
  PROCEDURE ^ ParseStatementSeq(VAR p: Parser): SyntaxTree.StatementNode;
  PROCEDURE ^ ParseDeclSeq(VAR p: Parser): SyntaxTree.DeclSeqNode;

  (* ---- Designators and expressions ---- *)

  PROCEDURE ParseExprList(VAR p: Parser): SyntaxTree.ExprNode;
    VAR head, tail, node: SyntaxTree.ExprNode;
  BEGIN
    head := ParseExpr(p); tail := head;
    WHILE p.current.kind = Lexer.comma DO
      Advance(p);
      node := ParseExpr(p);
      tail.next := node; tail := node
    END;
    RETURN head
  END ParseExprList;

  (* Speculatively parses a mid-chain type guard "(" Qualident ")" - see
     this module's own header comment, simplification 2. Only ever
     commits (returns TRUE, with sel holding the new GuardSelector) when
     the parenthesized content is exactly a bare, possibly
     module-qualified identifier immediately followed by another
     selector token - the one shape that can never be ActualParameters
     instead. Every other shape rolls the parser all the way back to
     before "(" (a plain record assignment, no pointers mutated in
     between - see Parser's own field comments - so this is an exact,
     cheap restore) and returns FALSE, leaving the "(" for the caller's
     existing ActualParameters/terminal-guard handling. Mirrors
     ParseQualident's own module-qualifier check (IsKnownAlias) rather
     than calling ParseQualident/ExpectIdent/ExpectToken directly, since
     those report diagnostics on a mismatch - an abandoned trial must
     leave no trace. *)
  PROCEDURE TryParseGuardSelector(VAR p: Parser; VAR sel: SyntaxTree.Selector): BOOLEAN;
    VAR saved: Parser; qualifier, name: SyntaxTree.Ident; line, column: INTEGER;
  BEGIN
    saved := p;
    line := p.current.line; column := p.current.column;
    Advance(p); (* past "(" *)
    IF p.current.kind # Lexer.ident THEN p := saved; RETURN FALSE END;
    COPY(p.current.lexeme, name); Advance(p);
    qualifier[0] := 0X;
    IF (p.current.kind = Lexer.period) & IsKnownAlias(p, name) THEN
      Advance(p);
      IF p.current.kind # Lexer.ident THEN p := saved; RETURN FALSE END;
      qualifier := name; COPY(p.current.lexeme, name); Advance(p)
    END;
    IF p.current.kind # Lexer.rightParen THEN p := saved; RETURN FALSE END;
    Advance(p); (* past ")" *)
    IF (p.current.kind # Lexer.period) & (p.current.kind # Lexer.leftBracket)
        & (p.current.kind # Lexer.caret) & (p.current.kind # Lexer.leftParen) THEN
      p := saved; RETURN FALSE
    END;
    sel := SemanticActions.NewGuardSelector(qualifier, name, line, column);
    RETURN TRUE
  END TryParseGuardSelector;

  PROCEDURE ParseDesignator(VAR p: Parser): SyntaxTree.Designator;
    VAR
      qualifier, name, fieldName: SyntaxTree.Ident;
      d: SyntaxTree.Designator;
      tail, sel: SyntaxTree.Selector;
      indices: SyntaxTree.ExprNode;
      line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ParseQualident(p, qualifier, name);
    d := SemanticActions.NewDesignator(qualifier, name, line, column);
    tail := NIL;
    LOOP
      line := p.current.line; column := p.current.column;
      IF p.current.kind = Lexer.period THEN
        Advance(p);
        ExpectIdent(p, fieldName);
        sel := SemanticActions.NewFieldSelector(fieldName, line, column)
      ELSIF p.current.kind = Lexer.leftBracket THEN
        Advance(p);
        indices := ParseExprList(p);
        ExpectToken(p, Lexer.rightBracket, "expected ']'");
        sel := SemanticActions.NewIndexSelector(indices, line, column)
      ELSIF p.current.kind = Lexer.caret THEN
        Advance(p);
        sel := SemanticActions.NewDereferenceSelector(line, column)
      ELSIF (p.current.kind = Lexer.leftParen) & TryParseGuardSelector(p, sel) THEN
        (* sel already built by TryParseGuardSelector *)
      ELSE
        EXIT
      END;
      IF tail = NIL THEN d.selectors := sel ELSE tail.next := sel END;
      tail := sel
    END;
    RETURN d
  END ParseDesignator;

  PROCEDURE ParseSet(VAR p: Parser): SyntaxTree.SetExprNode;
    VAR
      head, tail, el: SyntaxTree.SetElementNode;
      low, high: SyntaxTree.ExprNode;
      line, column, elLine, elColumn: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ExpectToken(p, Lexer.leftBrace, "expected '{'");
    head := NIL; tail := NIL;
    IF p.current.kind # Lexer.rightBrace THEN
      LOOP
        elLine := p.current.line; elColumn := p.current.column;
        low := ParseExpr(p);
        IF p.current.kind = Lexer.upTo THEN
          Advance(p); high := ParseExpr(p)
        ELSE
          high := NIL
        END;
        el := SemanticActions.NewSetElement(low, high, elLine, elColumn);
        IF tail = NIL THEN head := el ELSE tail.next := el END;
        tail := el;
        IF p.current.kind = Lexer.comma THEN Advance(p) ELSE EXIT END
      END
    END;
    ExpectToken(p, Lexer.rightBrace, "expected '}'");
    RETURN SemanticActions.NewSetExpr(head, line, column)
  END ParseSet;

  PROCEDURE ParseFactor(VAR p: Parser): SyntaxTree.ExprNode;
    VAR
      designator: SyntaxTree.Designator;
      hasParens: BOOLEAN;
      args, inner, operand: SyntaxTree.ExprNode;
      line, column: INTEGER;
      lexeme: SyntaxTree.Ident;
      literalKind: INTEGER;
      isHex, isLongReal: BOOLEAN;
  BEGIN
    line := p.current.line; column := p.current.column;
    IF p.current.kind = Lexer.ident THEN
      designator := ParseDesignator(p);
      hasParens := FALSE; args := NIL;
      IF p.current.kind = Lexer.leftParen THEN
        hasParens := TRUE; Advance(p);
        IF p.current.kind # Lexer.rightParen THEN args := ParseExprList(p) END;
        ExpectToken(p, Lexer.rightParen, "expected ')'")
      END;
      RETURN SemanticActions.NewDesignatorExpr(designator, hasParens, args, line, column)
    ELSIF (p.current.kind = Lexer.integer) OR (p.current.kind = Lexer.real)
        OR (p.current.kind = Lexer.charConst) OR (p.current.kind = Lexer.string) THEN
      literalKind := p.current.kind;
      COPY(p.current.lexeme, lexeme);
      isHex := p.current.isHex; isLongReal := p.current.isLongReal;
      Advance(p);
      RETURN SemanticActions.NewLiteralExpr(literalKind, lexeme, isHex, isLongReal, line, column)
    ELSIF p.current.kind = Lexer.nilKeyword THEN
      Advance(p);
      RETURN SemanticActions.NewNilExpr(line, column)
    ELSIF p.current.kind = Lexer.leftBrace THEN
      RETURN ParseSet(p)
    ELSIF p.current.kind = Lexer.leftParen THEN
      Advance(p);
      inner := ParseExpr(p);
      ExpectToken(p, Lexer.rightParen, "expected ')'");
      RETURN inner
    ELSIF p.current.kind = Lexer.tilde THEN
      Advance(p);
      operand := ParseFactor(p);
      RETURN SemanticActions.NewUnaryExpr(Lexer.tilde, operand, line, column)
    ELSE
      Diagnostics.Error(line, column, "expected an expression");
      Advance(p);
      RETURN SemanticActions.NewNilExpr(line, column)
    END
  END ParseFactor;

  PROCEDURE ParseTerm(VAR p: Parser): SyntaxTree.ExprNode;
    VAR left, right: SyntaxTree.ExprNode; op, line, column: INTEGER;
  BEGIN
    left := ParseFactor(p);
    WHILE IsMulOp(p.current.kind) DO
      op := p.current.kind; line := p.current.line; column := p.current.column;
      Advance(p);
      right := ParseFactor(p);
      left := SemanticActions.NewBinaryExpr(op, left, right, line, column)
    END;
    RETURN left
  END ParseTerm;

  PROCEDURE ParseSimpleExpr(VAR p: Parser): SyntaxTree.ExprNode;
    VAR result, right: SyntaxTree.ExprNode; sign, op, line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    sign := 0;
    IF (p.current.kind = Lexer.plus) OR (p.current.kind = Lexer.minus) THEN
      sign := p.current.kind; Advance(p)
    END;
    result := ParseTerm(p);
    IF sign = Lexer.minus THEN
      result := SemanticActions.NewUnaryExpr(Lexer.minus, result, line, column)
    END;
    WHILE IsAddOp(p.current.kind) DO
      op := p.current.kind; line := p.current.line; column := p.current.column;
      Advance(p);
      right := ParseTerm(p);
      result := SemanticActions.NewBinaryExpr(op, result, right, line, column)
    END;
    RETURN result
  END ParseSimpleExpr;

  PROCEDURE ParseExpr(VAR p: Parser): SyntaxTree.ExprNode;
    VAR left, right: SyntaxTree.ExprNode; op, line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    left := ParseSimpleExpr(p);
    IF IsRelation(p.current.kind) THEN
      op := p.current.kind; Advance(p);
      right := ParseSimpleExpr(p);
      left := SemanticActions.NewBinaryExpr(op, left, right, line, column)
    END;
    RETURN left
  END ParseExpr;

  (* ---- Types ---- *)

  PROCEDURE ParseFieldList(VAR p: Parser): SyntaxTree.FieldListNode;
    VAR
      names: SyntaxTree.IdentDefNode;
      type: SyntaxTree.TypeNode;
      line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    IF p.current.kind = Lexer.ident THEN
      names := ParseIdentList(p);
      ExpectToken(p, Lexer.colon, "expected ':'");
      type := ParseType(p)
    ELSE
      names := NIL; type := NIL
    END;
    RETURN SemanticActions.NewFieldList(names, type, line, column)
  END ParseFieldList;

  PROCEDURE ParseFPSection(VAR p: Parser): SyntaxTree.FPSectionNode;
    VAR
      isVar: BOOLEAN;
      names: SyntaxTree.IdentDefNode;
      type: SyntaxTree.TypeNode;
      line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    isVar := FALSE;
    IF p.current.kind = Lexer.varKeyword THEN isVar := TRUE; Advance(p) END;
    names := ParseParamNames(p);
    ExpectToken(p, Lexer.colon, "expected ':'");
    type := ParseType(p);
    RETURN SemanticActions.NewFPSection(isVar, names, type, line, column)
  END ParseFPSection;

  PROCEDURE ParseFormalPars(VAR p: Parser): SyntaxTree.FormalParsNode;
    VAR
      head, tail, section: SyntaxTree.FPSectionNode;
      returnType: SyntaxTree.QualidentTypeNode;
      qualifier, name: SyntaxTree.Ident;
      line, column, rtLine, rtColumn: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ExpectToken(p, Lexer.leftParen, "expected '('");
    head := NIL; tail := NIL;
    IF p.current.kind # Lexer.rightParen THEN
      head := ParseFPSection(p); tail := head;
      WHILE p.current.kind = Lexer.semicolon DO
        Advance(p);
        section := ParseFPSection(p);
        tail.next := section; tail := section
      END
    END;
    ExpectToken(p, Lexer.rightParen, "expected ')'");
    returnType := NIL;
    IF p.current.kind = Lexer.colon THEN
      rtLine := p.current.line; rtColumn := p.current.column;
      Advance(p);
      ParseQualident(p, qualifier, name);
      returnType := SemanticActions.NewQualidentType(qualifier, name, rtLine, rtColumn)
    END;
    RETURN SemanticActions.NewFormalPars(head, returnType, line, column)
  END ParseFormalPars;

  PROCEDURE ParseType(VAR p: Parser): SyntaxTree.TypeNode;
    VAR
      qualifier, name: SyntaxTree.Ident;
      line, column: INTEGER;
      lengths, len: SyntaxTree.ExprNode;
      lenTail: SyntaxTree.ExprNode;
      elementType, base: SyntaxTree.TypeNode;
      baseType: SyntaxTree.QualidentTypeNode;
      head, tail, field: SyntaxTree.FieldListNode;
      formals: SyntaxTree.FormalParsNode;
  BEGIN
    line := p.current.line; column := p.current.column;
    IF p.current.kind = Lexer.ident THEN
      ParseQualident(p, qualifier, name);
      RETURN SemanticActions.NewQualidentType(qualifier, name, line, column)
    ELSIF p.current.kind = Lexer.arrayKeyword THEN
      Advance(p);
      lengths := NIL; lenTail := NIL;
      IF p.current.kind # Lexer.ofKeyword THEN
        len := ParseExpr(p); lengths := len; lenTail := len;
        WHILE p.current.kind = Lexer.comma DO
          Advance(p);
          len := ParseExpr(p);
          lenTail.next := len; lenTail := len
        END
      END;
      ExpectToken(p, Lexer.ofKeyword, "expected 'OF'");
      elementType := ParseType(p);
      RETURN SemanticActions.NewArrayType(lengths, elementType, line, column)
    ELSIF p.current.kind = Lexer.recordKeyword THEN
      Advance(p);
      baseType := NIL;
      IF p.current.kind = Lexer.leftParen THEN
        Advance(p);
        ParseQualident(p, qualifier, name);
        baseType := SemanticActions.NewQualidentType(qualifier, name, line, column);
        ExpectToken(p, Lexer.rightParen, "expected ')'")
      END;
      head := ParseFieldList(p); tail := head;
      WHILE p.current.kind = Lexer.semicolon DO
        Advance(p);
        field := ParseFieldList(p);
        tail.next := field; tail := field
      END;
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewRecordType(baseType, head, line, column)
    ELSIF p.current.kind = Lexer.pointerKeyword THEN
      Advance(p);
      ExpectToken(p, Lexer.toKeyword, "expected 'TO'");
      base := ParseType(p);
      RETURN SemanticActions.NewPointerType(base, line, column)
    ELSIF p.current.kind = Lexer.procedureKeyword THEN
      Advance(p);
      formals := NIL;
      IF p.current.kind = Lexer.leftParen THEN formals := ParseFormalPars(p) END;
      RETURN SemanticActions.NewProcedureType(formals, line, column)
    ELSE
      Diagnostics.Error(line, column, "expected a type");
      Advance(p);
      RETURN SemanticActions.NewQualidentType("", "", line, column)
    END
  END ParseType;

  (* ---- Receiver ---- *)

  PROCEDURE ParseReceiver(VAR p: Parser): SyntaxTree.ReceiverNode;
    VAR isVar: BOOLEAN; name, typeName: SyntaxTree.Ident; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ExpectToken(p, Lexer.leftParen, "expected '('");
    isVar := FALSE;
    IF p.current.kind = Lexer.varKeyword THEN isVar := TRUE; Advance(p) END;
    ExpectIdent(p, name);
    ExpectToken(p, Lexer.colon, "expected ':'");
    ExpectIdent(p, typeName);
    ExpectToken(p, Lexer.rightParen, "expected ')'");
    RETURN SemanticActions.NewReceiver(isVar, name, typeName, line, column)
  END ParseReceiver;

  (* ---- Statements ---- *)

  PROCEDURE ParseCaseLabel(VAR p: Parser): SyntaxTree.CaseLabelNode;
    VAR low, high: SyntaxTree.ExprNode; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    low := ParseExpr(p);
    high := NIL;
    IF p.current.kind = Lexer.upTo THEN Advance(p); high := ParseExpr(p) END;
    RETURN SemanticActions.NewCaseLabel(low, high, line, column)
  END ParseCaseLabel;

  PROCEDURE ParseCase(VAR p: Parser): SyntaxTree.CaseNode;
    VAR
      head, tail, label: SyntaxTree.CaseLabelNode;
      body: SyntaxTree.StatementNode;
      line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    IF (p.current.kind = Lexer.verticalBar) OR (p.current.kind = Lexer.elseKeyword)
        OR (p.current.kind = Lexer.endKeyword) THEN
      RETURN NIL (* an empty case arm *)
    END;
    head := ParseCaseLabel(p); tail := head;
    WHILE p.current.kind = Lexer.comma DO
      Advance(p);
      label := ParseCaseLabel(p);
      tail.next := label; tail := label
    END;
    ExpectToken(p, Lexer.colon, "expected ':'");
    body := ParseStatementSeq(p);
    RETURN SemanticActions.NewCase(head, body, line, column)
  END ParseCase;

  PROCEDURE ParseGuard(VAR p: Parser; VAR variableQualifier, variableName,
                        typeQualifier, typeName: SyntaxTree.Ident);
  BEGIN
    ParseQualident(p, variableQualifier, variableName);
    ExpectToken(p, Lexer.colon, "expected ':'");
    ParseQualident(p, typeQualifier, typeName)
  END ParseGuard;

  PROCEDURE ParseStatement(VAR p: Parser): SyntaxTree.StatementNode;
    VAR
      line, column: INTEGER;
      designator: SyntaxTree.Designator;
      expr, value: SyntaxTree.ExprNode;
      hasParens: BOOLEAN;
      args: SyntaxTree.ExprNode;
      branches, branchTail, branch: SyntaxTree.IfBranchNode;
      elseBody, body: SyntaxTree.StatementNode;
      hasElse: BOOLEAN;
      cases, caseTail, caseNode: SyntaxTree.CaseNode;
      variable: SyntaxTree.Ident;
      start, stop, step: SyntaxTree.ExprNode;
      guards, guardTail, guard: SyntaxTree.WithGuardNode;
      variableQualifier, variableName, typeQualifier, typeName: SyntaxTree.Ident;
  BEGIN
    line := p.current.line; column := p.current.column;
    IF p.current.kind = Lexer.ident THEN
      designator := ParseDesignator(p);
      IF p.current.kind = Lexer.assign THEN
        Advance(p);
        value := ParseExpr(p);
        RETURN SemanticActions.NewAssignStatement(designator, value, line, column)
      ELSE
        hasParens := FALSE; args := NIL;
        IF p.current.kind = Lexer.leftParen THEN
          hasParens := TRUE; Advance(p);
          IF p.current.kind # Lexer.rightParen THEN args := ParseExprList(p) END;
          ExpectToken(p, Lexer.rightParen, "expected ')'")
        END;
        RETURN SemanticActions.NewCallStatement(designator, hasParens, args, line, column)
      END
    ELSIF p.current.kind = Lexer.ifKeyword THEN
      Advance(p);
      expr := ParseExpr(p);
      ExpectToken(p, Lexer.thenKeyword, "expected 'THEN'");
      body := ParseStatementSeq(p);
      branches := SemanticActions.NewIfBranch(expr, body, line, column);
      branchTail := branches;
      WHILE p.current.kind = Lexer.elsifKeyword DO
        line := p.current.line; column := p.current.column;
        Advance(p);
        expr := ParseExpr(p);
        ExpectToken(p, Lexer.thenKeyword, "expected 'THEN'");
        body := ParseStatementSeq(p);
        branch := SemanticActions.NewIfBranch(expr, body, line, column);
        branchTail.next := branch; branchTail := branch
      END;
      elseBody := NIL;
      IF p.current.kind = Lexer.elseKeyword THEN
        Advance(p); elseBody := ParseStatementSeq(p)
      END;
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewIfStatement(branches, elseBody, line, column)
    ELSIF p.current.kind = Lexer.caseKeyword THEN
      Advance(p);
      expr := ParseExpr(p);
      ExpectToken(p, Lexer.ofKeyword, "expected 'OF'");
      cases := ParseCase(p); caseTail := cases;
      WHILE p.current.kind = Lexer.verticalBar DO
        Advance(p);
        caseNode := ParseCase(p);
        IF caseTail = NIL THEN cases := caseNode ELSE caseTail.next := caseNode END;
        IF caseNode # NIL THEN caseTail := caseNode END
      END;
      elseBody := NIL; hasElse := FALSE;
      IF p.current.kind = Lexer.elseKeyword THEN
        Advance(p); elseBody := ParseStatementSeq(p); hasElse := TRUE
      END;
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewCaseStatement(expr, cases, elseBody, hasElse, line, column)
    ELSIF p.current.kind = Lexer.whileKeyword THEN
      Advance(p);
      expr := ParseExpr(p);
      ExpectToken(p, Lexer.doKeyword, "expected 'DO'");
      body := ParseStatementSeq(p);
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewWhileStatement(expr, body, line, column)
    ELSIF p.current.kind = Lexer.repeatKeyword THEN
      Advance(p);
      body := ParseStatementSeq(p);
      ExpectToken(p, Lexer.untilKeyword, "expected 'UNTIL'");
      expr := ParseExpr(p);
      RETURN SemanticActions.NewRepeatStatement(body, expr, line, column)
    ELSIF p.current.kind = Lexer.forKeyword THEN
      Advance(p);
      ExpectIdent(p, variable);
      ExpectToken(p, Lexer.assign, "expected ':='");
      start := ParseExpr(p);
      ExpectToken(p, Lexer.toKeyword, "expected 'TO'");
      stop := ParseExpr(p);
      step := NIL;
      IF p.current.kind = Lexer.byKeyword THEN Advance(p); step := ParseExpr(p) END;
      ExpectToken(p, Lexer.doKeyword, "expected 'DO'");
      body := ParseStatementSeq(p);
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewForStatement(variable, start, stop, step, body, line, column)
    ELSIF p.current.kind = Lexer.loopKeyword THEN
      Advance(p);
      body := ParseStatementSeq(p);
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewLoopStatement(body, line, column)
    ELSIF p.current.kind = Lexer.withKeyword THEN
      Advance(p);
      ParseGuard(p, variableQualifier, variableName, typeQualifier, typeName);
      ExpectToken(p, Lexer.doKeyword, "expected 'DO'");
      body := ParseStatementSeq(p);
      guards := SemanticActions.NewWithGuard(variableQualifier, variableName,
                                              typeQualifier, typeName, body, line, column);
      guardTail := guards;
      WHILE p.current.kind = Lexer.verticalBar DO
        line := p.current.line; column := p.current.column;
        Advance(p);
        ParseGuard(p, variableQualifier, variableName, typeQualifier, typeName);
        ExpectToken(p, Lexer.doKeyword, "expected 'DO'");
        body := ParseStatementSeq(p);
        guard := SemanticActions.NewWithGuard(variableQualifier, variableName,
                                               typeQualifier, typeName, body, line, column);
        guardTail.next := guard; guardTail := guard
      END;
      elseBody := NIL; hasElse := FALSE;
      IF p.current.kind = Lexer.elseKeyword THEN
        Advance(p); elseBody := ParseStatementSeq(p); hasElse := TRUE
      END;
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      RETURN SemanticActions.NewWithStatement(guards, elseBody, hasElse, line, column)
    ELSIF p.current.kind = Lexer.exitKeyword THEN
      Advance(p);
      RETURN SemanticActions.NewExitStatement(line, column)
    ELSIF p.current.kind = Lexer.returnKeyword THEN
      Advance(p);
      value := NIL;
      IF (p.current.kind # Lexer.semicolon) & (p.current.kind # Lexer.endKeyword)
          & (p.current.kind # Lexer.elseKeyword) & (p.current.kind # Lexer.elsifKeyword)
          & (p.current.kind # Lexer.untilKeyword) & (p.current.kind # Lexer.verticalBar)
          & (p.current.kind # Lexer.eof) THEN
        value := ParseExpr(p)
      END;
      RETURN SemanticActions.NewReturnStatement(value, line, column)
    ELSE
      RETURN NIL (* an empty statement *)
    END
  END ParseStatement;

  PROCEDURE ParseStatementSeq(VAR p: Parser): SyntaxTree.StatementNode;
    VAR head, tail, node: SyntaxTree.StatementNode;
  BEGIN
    head := ParseStatement(p); tail := head;
    WHILE p.current.kind = Lexer.semicolon DO
      Advance(p);
      node := ParseStatement(p);
      IF node # NIL THEN
        IF tail = NIL THEN head := node ELSE tail.next := node END;
        tail := node
      END
    END;
    RETURN head
  END ParseStatementSeq;

  (* ---- Declarations ---- *)

  PROCEDURE ParseConstDecl(VAR p: Parser): SyntaxTree.ConstDeclNode;
    VAR name: SyntaxTree.IdentDefNode; value: SyntaxTree.ExprNode; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    name := ParseIdentDef(p);
    ExpectToken(p, Lexer.equal, "expected '='");
    value := ParseExpr(p);
    RETURN SemanticActions.NewConstDecl(name, value, line, column)
  END ParseConstDecl;

  PROCEDURE ParseTypeDecl(VAR p: Parser): SyntaxTree.TypeDeclNode;
    VAR name: SyntaxTree.IdentDefNode; type: SyntaxTree.TypeNode; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    name := ParseIdentDef(p);
    ExpectToken(p, Lexer.equal, "expected '='");
    type := ParseType(p);
    RETURN SemanticActions.NewTypeDecl(name, type, line, column)
  END ParseTypeDecl;

  PROCEDURE ParseVarDecl(VAR p: Parser): SyntaxTree.VarDeclNode;
    VAR names: SyntaxTree.IdentDefNode; type: SyntaxTree.TypeNode; line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    names := ParseIdentList(p);
    ExpectToken(p, Lexer.colon, "expected ':'");
    type := ParseType(p);
    RETURN SemanticActions.NewVarDecl(names, type, line, column)
  END ParseVarDecl;

  (* "[" string [ "," string ] "]" right after PROCEDURE - the already-
     decided external-procedure-declaration syntax (AGENTS.md, "External
     procedures"; PLAN.md's "Open design questions"). Lexer.ScanString
     strips the surrounding quotes itself, so p.current.lexeme is already
     the bare convention/name text. *)
  PROCEDURE ParseExternalAttribute(VAR p: Parser; VAR convention, name: SyntaxTree.Ident);
  BEGIN
    ExpectToken(p, Lexer.leftBracket, "expected '['");
    IF p.current.kind = Lexer.string THEN
      COPY(p.current.lexeme, convention); Advance(p)
    ELSE
      Diagnostics.Error(p.current.line, p.current.column, "expected a calling-convention string");
      convention[0] := 0X
    END;
    name[0] := 0X;
    IF p.current.kind = Lexer.comma THEN
      Advance(p);
      IF p.current.kind = Lexer.string THEN
        COPY(p.current.lexeme, name); Advance(p)
      ELSE
        Diagnostics.Error(p.current.line, p.current.column, "expected an external-name string")
      END
    END;
    ExpectToken(p, Lexer.rightBracket, "expected ']'")
  END ParseExternalAttribute;

  PROCEDURE ParseProcDecl(VAR p: Parser; isForward, isExternal: BOOLEAN;
                          externalConvention, externalName: SyntaxTree.Ident;
                          line, column: INTEGER): SyntaxTree.ProcDeclNode;
    VAR
      receiver: SyntaxTree.ReceiverNode;
      name: SyntaxTree.IdentDefNode;
      formals: SyntaxTree.FormalParsNode;
      declarations: SyntaxTree.DeclSeqNode;
      statements: SyntaxTree.StatementNode;
      endName: SyntaxTree.Ident;
  BEGIN
    receiver := NIL;
    (* An external procedure is never type-bound (AGENTS.md); a receiver
       written on one is left to misparse its "(" as FormalPars rather
       than specially accommodated - see PLAN.md's own note on this. *)
    IF ~isExternal & (p.current.kind = Lexer.leftParen) THEN receiver := ParseReceiver(p) END;
    name := ParseIdentDef(p);
    formals := NIL;
    IF p.current.kind = Lexer.leftParen THEN formals := ParseFormalPars(p) END;
    declarations := NIL; statements := NIL; endName[0] := 0X;
    IF ~isForward & ~isExternal THEN
      ExpectToken(p, Lexer.semicolon, "expected ';'");
      declarations := ParseDeclSeq(p);
      IF p.current.kind = Lexer.beginKeyword THEN
        Advance(p); statements := ParseStatementSeq(p)
      END;
      ExpectToken(p, Lexer.endKeyword, "expected 'END'");
      ExpectIdent(p, endName);
      IF endName # name.name THEN
        Diagnostics.Error(line, column, "procedure END identifier does not match its name")
      END
    END;
    RETURN SemanticActions.NewProcDecl(isForward, isExternal, externalConvention, externalName,
                                        receiver, name, formals,
                                        declarations, statements, endName, line, column)
  END ParseProcDecl;

  PROCEDURE ParseDeclSeq(VAR p: Parser): SyntaxTree.DeclSeqNode;
    VAR
      constHead, constTail, constNode: SyntaxTree.ConstDeclNode;
      typeHead, typeTail, typeNode: SyntaxTree.TypeDeclNode;
      varHead, varTail, varNode: SyntaxTree.VarDeclNode;
      procHead, procTail, procNode: SyntaxTree.ProcDeclNode;
      line, column: INTEGER;
      isForward, isExternal: BOOLEAN;
      externalConvention, externalName: SyntaxTree.Ident;
  BEGIN
    line := p.current.line; column := p.current.column;
    constHead := NIL; constTail := NIL;
    typeHead := NIL; typeTail := NIL;
    varHead := NIL; varTail := NIL;
    procHead := NIL; procTail := NIL;
    LOOP
      IF p.current.kind = Lexer.constKeyword THEN
        Advance(p);
        WHILE p.current.kind = Lexer.ident DO
          constNode := ParseConstDecl(p);
          ExpectToken(p, Lexer.semicolon, "expected ';'");
          IF constTail = NIL THEN constHead := constNode ELSE constTail.next := constNode END;
          constTail := constNode
        END
      ELSIF p.current.kind = Lexer.typeKeyword THEN
        Advance(p);
        WHILE p.current.kind = Lexer.ident DO
          typeNode := ParseTypeDecl(p);
          ExpectToken(p, Lexer.semicolon, "expected ';'");
          IF typeTail = NIL THEN typeHead := typeNode ELSE typeTail.next := typeNode END;
          typeTail := typeNode
        END
      ELSIF p.current.kind = Lexer.varKeyword THEN
        Advance(p);
        WHILE p.current.kind = Lexer.ident DO
          varNode := ParseVarDecl(p);
          ExpectToken(p, Lexer.semicolon, "expected ';'");
          IF varTail = NIL THEN varHead := varNode ELSE varTail.next := varNode END;
          varTail := varNode
        END
      ELSE
        EXIT
      END
    END;
    WHILE p.current.kind = Lexer.procedureKeyword DO
      line := p.current.line; column := p.current.column;
      Advance(p);
      isForward := FALSE; isExternal := FALSE;
      externalConvention[0] := 0X; externalName[0] := 0X;
      IF p.current.kind = Lexer.caret THEN
        isForward := TRUE; Advance(p)
      ELSIF p.current.kind = Lexer.leftBracket THEN
        isExternal := TRUE;
        ParseExternalAttribute(p, externalConvention, externalName)
      END;
      procNode := ParseProcDecl(p, isForward, isExternal, externalConvention, externalName,
                                 line, column);
      ExpectToken(p, Lexer.semicolon, "expected ';'");
      IF procTail = NIL THEN procHead := procNode ELSE procTail.next := procNode END;
      procTail := procNode
    END;
    RETURN SemanticActions.NewDeclSeq(constHead, typeHead, varHead, procHead, line, column)
  END ParseDeclSeq;

  (* ---- Imports and modules ---- *)

  PROCEDURE ParseImportList(VAR p: Parser): SyntaxTree.ImportNode;
    VAR
      head, tail, node: SyntaxTree.ImportNode;
      first, alias, moduleName: SyntaxTree.Ident;
      line, column: INTEGER;
  BEGIN
    ExpectToken(p, Lexer.importKeyword, "expected 'IMPORT'");
    head := NIL; tail := NIL;
    LOOP
      line := p.current.line; column := p.current.column;
      ExpectIdent(p, first);
      IF p.current.kind = Lexer.assign THEN
        Advance(p);
        ExpectIdent(p, moduleName);
        alias := first
      ELSE
        moduleName := first; alias[0] := 0X
      END;
      node := SemanticActions.NewImport(alias, moduleName, line, column);
      IF tail = NIL THEN head := node ELSE tail.next := node END;
      tail := node;
      IF alias[0] # 0X THEN AddAlias(p, alias) ELSE AddAlias(p, moduleName) END;
      IF p.current.kind = Lexer.comma THEN Advance(p) ELSE EXIT END
    END;
    ExpectToken(p, Lexer.semicolon, "expected ';'");
    RETURN head
  END ParseImportList;

  PROCEDURE InitParser*(VAR p: Parser; text: Lexer.CharBuffer; length: LONGINT);
  BEGIN
    Lexer.InitScanner(p.scanner, text, length);
    Lexer.NextToken(p.scanner, p.current);
    p.aliases := NIL
  END InitParser;

  PROCEDURE ParseModule*(VAR p: Parser): SyntaxTree.ModuleNode;
    VAR
      name, endName: SyntaxTree.Ident;
      imports: SyntaxTree.ImportNode;
      declarations: SyntaxTree.DeclSeqNode;
      statements: SyntaxTree.StatementNode;
      line, column: INTEGER;
  BEGIN
    line := p.current.line; column := p.current.column;
    ExpectToken(p, Lexer.moduleKeyword, "expected 'MODULE'");
    ExpectIdent(p, name);
    ExpectToken(p, Lexer.semicolon, "expected ';'");
    imports := NIL;
    IF p.current.kind = Lexer.importKeyword THEN imports := ParseImportList(p) END;
    declarations := ParseDeclSeq(p);
    statements := NIL;
    IF p.current.kind = Lexer.beginKeyword THEN
      Advance(p); statements := ParseStatementSeq(p)
    END;
    ExpectToken(p, Lexer.endKeyword, "expected 'END'");
    ExpectIdent(p, endName);
    ExpectToken(p, Lexer.period, "expected '.'");
    IF endName # name THEN
      Diagnostics.Error(line, column, "module END identifier does not match its name")
    END;
    RETURN SemanticActions.NewModule(name, imports, declarations, statements, endName, line, column)
  END ParseModule;

END Parser.
